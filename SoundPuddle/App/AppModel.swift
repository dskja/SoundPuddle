import AVFoundation
import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case home
        case hostSetup
        case hostLive
        case joinBrowse
        case joinConnecting
        case joinCalibrate
        case joinLive
    }

    enum HostSource: Equatable {
        case microphone
        case file(URL)
    }

    // MARK: View-facing state (Features contract)
    var route: Route = .home
    var sessionTitle = ""
    var sessionMode: SessionMode = .schwarm
    var hostSource: HostSource = .microphone
    var discovered: [(peer: MeshPeer, ad: SessionAdvertisement)] = []
    var peers: [MeshPeer] = []
    var audioLevel: Float = 0
    var linkQuality: LinkQuality = .good
    var lastError: String?
    var isStreaming = false
    var showPermissionHint = false
    var displayName: String = UserDefaults.standard.string(forKey: "displayName") ?? UIDevice.current.name
    var underrunCountPublic: Int { underrunCount }
    var isLiveContainer: Bool { LiveContainerRuntime.isActive }
    var importedFileLabel: String? {
        if case .file(let url) = hostSource { return url.lastPathComponent }
        return nil
    }

    var isStreamPaused = false
    var hostMonitorMuted = true
    var joinVolume: Float = 1
    var isMuted = false
    var rosterNames: [String] = []
    var lastRTT: Int?
    var sessionStartedAt: Date?

    var sessionElapsedLabel: String {
        guard let start = sessionStartedAt else { return "00:00" }
        let secs = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    var rttLabel: String {
        lastRTT.map { "\($0) ms" } ?? "—"
    }

    var diagnosticsLine: String {
        let lc = isLiveContainer ? "LC" : "native"
        let pause = isStreamPaused ? " · paused" : ""
        return "\(lc) · \(myRole.rawValue) · peers \(peers.count)/7 · underrun \(underrunCount) · \(linkQuality.rawValue) · rtt \(rttLabel)\(pause)"
    }

    var peerCapWarning: Bool { peers.count >= 6 }

    // MARK: Schwarm
    var fieldMap: FieldMap = .empty
    var myRole: SpeakerRole = .mid
    var calibrateProgress: Double = 0
    var calibrateStatus = ""
    var playlistTracks: [PlaylistTrack] = []
    var currentTrackID: String?
    var lightFlash: Double = 0
    var lightshowEnabled = true
    var deviceProfile = DeviceProfiler.profile()
    var proximityReady = false
    var dragProgress: CGFloat = 0

    var roleLabel: String {
        String(localized: String.LocalizationValue(myRole.titleKey))
    }

    // MARK: Internals
    private let mesh: any MeshTransporting
    private let capture = AudioCaptureEngine()
    private let playback = AudioPlaybackEngine()
    private let sessionConfig = AudioSessionConfigurator()
    private let networkPrimer = LocalNetworkPrimer()
    private let clock = ClockSync()
    private let chirp = ChirpCalibrator()
    private let lightshow = LightshowController()
    private let playlist = PlaylistEngine()
    private var eventTask: Task<Void, Never>?
    private var joinTimeoutTask: Task<Void, Never>?
    private var qualityRecoveryTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var clockSyncTask: Task<Void, Never>?
    private var underrunCount = 0
    private var activeAdvertisement: SessionAdvertisement?
    private var sessionActive = false
    private var idleTimerHeld = false
    private var welcomedPeerIDs = Set<String>()
    private var pendingPingT: Int64?
    private var interruptionObserver: NSObjectProtocol?
    private var chirpDistances: [String: Double] = [:]
    private var chirpRound = 0
    private var hostPlayEpochMs: Int64?
    private var lastLightCueMs: Int64 = 0
    private var localPeerKey: String { "local:\(displayName)" }

    init(mesh: (any MeshTransporting)? = nil) {
        self.mesh = mesh ?? MultipeerMeshTransport()
        capture.onFrame = { [weak self] packet in
            Task { @MainActor in
                guard let self, self.isStreaming, !self.isStreamPaused else { return }
                self.mesh.sendAudio(packet, to: nil)
            }
        }
        capture.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.audioLevel = level
                if self.route == .hostLive {
                    self.lightshow.ingestLevel(level)
                    self.lightFlash = self.lightshow.screenFlash
                    self.maybeBroadcastLightCue(level: level)
                }
            }
        }
        playback.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.audioLevel = level
                if self.route == .joinLive {
                    self.lightshow.ingestLevel(level)
                    self.lightFlash = self.lightshow.screenFlash
                }
            }
        }
        playback.onUnderrun = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.underrunCount += 1
                self.linkQuality = self.underrunCount > 3 ? .weak : .okay
                self.scheduleQualityRecovery()
            }
        }
        capture.monitorMuted = hostMonitorMuted
        listen()
        networkPrimer.prime()
        observeAudioInterruptions()
    }

    // MARK: Navigation

    func openHost() {
        showPermissionHint = true
        lastError = nil
        sessionMode = .schwarm
        networkPrimer.prime()
        route = .hostSetup
    }

    func openJoin() {
        showPermissionHint = true
        lastError = nil
        proximityReady = false
        dragProgress = 0
        networkPrimer.prime()
        route = .joinBrowse
        startBrowsing()
    }

    func goHome() {
        teardownAll()
        route = .home
        lastError = nil
    }

    func updateDisplayName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        UserDefaults.standard.set(trimmed, forKey: "displayName")
        Haptics.light()
    }

    func importAudioFile(_ url: URL) {
        do {
            let local = try ImportedAudioStore.ingest(url)
            ImportedAudioStore.purgeOld()
            hostSource = .file(local)
            let title = local.deletingPathExtension().lastPathComponent
            playlist.replace(with: [PlaylistTrack(title: title, path: local.path)], current: nil)
            syncPlaylistUI()
            if sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sessionTitle = String(title.prefix(SessionAdvertisement.maxTitleLength))
            }
            lastError = nil
            Haptics.light()
        } catch {
            lastError = error.localizedDescription
            Haptics.warning()
        }
    }

    func setDragProgress(_ value: CGFloat) {
        dragProgress = min(1, max(0, value))
        if dragProgress > 0.92 { proximityReady = true }
    }

    // MARK: Host

    func startHosting() {
        let trimmed = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? String(localized: "host.defaultTitle") : trimmed
        sessionTitle = title
        sessionMode = .schwarm
        let ad = SessionAdvertisement(title: title, mode: sessionMode)
        activeAdvertisement = ad
        myRole = .mid
        playback.speakerRole = .mid

        Task {
            do {
                // LiveContainer: force Local Network permission BEFORE Multipeer advertise,
                // otherwise Bonjour fails with NSNetServicesErrorDomain -72008.
                await networkPrimer.primeAndWait()
                if case .microphone = hostSource {
                    try await requestMicrophonePermission()
                }
                try sessionConfig.configure(for: sessionMode, role: .host)
                mesh.acceptInvitations(true)
                mesh.startHosting(advertisement: ad)
                capture.monitorMuted = hostMonitorMuted
                switch hostSource {
                case .microphone:
                    try capture.start(source: .microphone)
                case .file(let url):
                    try capture.start(source: .file(url))
                    if playlist.tracks.isEmpty {
                        playlist.add(PlaylistTrack(title: url.deletingPathExtension().lastPathComponent, path: url.path))
                        syncPlaylistUI()
                    }
                }
                capture.setPaused(true)
                isStreaming = false
                isStreamPaused = true
                sessionActive = true
                sessionStartedAt = Date()
                holdIdleTimer(true)
                rebalanceField()
                broadcastPlaylist()
                startPingLoop()
                startElapsedTick()
                route = .hostLive
                Haptics.success()
            } catch {
                lastError = error.localizedDescription
                teardownAll()
                route = .hostSetup
                Haptics.warning()
            }
        }
    }

    func startSchwarm() {
        guard route == .hostLive else { return }
        Task {
            await runHostCalibration()
            beginHostStreamScheduled()
        }
    }

    func stopHosting() {
        mesh.sendControl(.streamStop(reason: "user"), to: nil)
        mesh.sendControl(.goodbye(reason: "host_stop"), to: nil)
        teardownAll()
        route = .home
    }

    func togglePause() {
        guard route == .hostLive else { return }
        isStreamPaused.toggle()
        if isStreamPaused {
            capture.setPaused(true)
            mesh.sendControl(.streamStop(reason: "pause"), to: nil)
            isStreaming = false
        } else {
            capture.setPaused(false)
            isStreaming = true
            sendStreamStart()
        }
        Haptics.light()
    }

    func toggleHostMonitor() {
        hostMonitorMuted.toggle()
        capture.monitorMuted = hostMonitorMuted
        Haptics.light()
    }

    func toggleLightshow() {
        lightshowEnabled.toggle()
        lightshow.enabled = lightshowEnabled
        if !lightshowEnabled {
            lightshow.stop()
            lightFlash = 0
        }
        Haptics.light()
    }

    func hostVote(trackID: String) {
        playlist.vote(trackID: trackID, from: localPeerKey)
        syncPlaylistUI()
        broadcastPlaylist()
    }

    func advancePlaylist() {
        guard route == .hostLive else { return }
        guard let next = playlist.advanceToWinner() else { return }
        syncPlaylistUI()
        broadcastPlaylist()
        if let path = next.path {
            let url = URL(fileURLWithPath: path)
            hostSource = .file(url)
            do {
                capture.stop()
                try capture.start(source: .file(url))
                capture.monitorMuted = hostMonitorMuted
                isStreaming = true
                isStreamPaused = false
                let startAt = ClockSync.nowMs() + 800
                mesh.sendControl(.playSchedule(.init(trackId: next.id, startHostMs: startAt)), to: nil)
                sendStreamStart()
            } catch {
                lastError = error.localizedDescription
            }
        }
        Haptics.success()
    }

    // MARK: Join

    func startBrowsing() {
        discovered = []
        Task {
            await networkPrimer.primeAndWait()
            mesh.startBrowsing()
        }
    }

    func join(peer: MeshPeer, advertisement: SessionAdvertisement) {
        if advertisement.protocolVersion != ProtocolVersion.major {
            lastError = AppError.protocolMismatch.errorDescription
            return
        }
        lastError = nil
        sessionTitle = advertisement.title
        sessionMode = advertisement.mode.isSchwarm ? .schwarm : advertisement.mode
        route = .joinConnecting
        mesh.invite(peer)
        joinTimeoutTask?.cancel()
        joinTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.route == .joinConnecting || self.route == .joinCalibrate {
                self.lastError = AppError.timeout.errorDescription
                self.teardownAll()
                self.route = .joinBrowse
                self.startBrowsing()
                Haptics.warning()
            }
        }
    }

    func leaveSession() {
        mesh.sendControl(.goodbye(reason: "leave"), to: nil)
        teardownAll()
        route = .home
    }

    func toggleMute() {
        isMuted.toggle()
        applyJoinVolume()
        Haptics.light()
    }

    func setJoinVolume(_ value: Float) {
        joinVolume = max(0, min(1, value))
        applyJoinVolume()
    }

    func castVote(trackID: String) {
        playlist.vote(trackID: trackID, from: localPeerKey)
        syncPlaylistUI()
        mesh.sendControl(.vote(.init(trackId: trackID, peerId: localPeerKey)), to: nil)
        Haptics.light()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if sessionActive { holdIdleTimer(true) }
            networkPrimer.prime()
        case .inactive, .background:
            break
        @unknown default:
            break
        }
    }

    // MARK: Event loop

    private func listen() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.mesh.events {
                if Task.isCancelled { break }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: MeshEvent) {
        switch event {
        case .peerDiscovered(let peer, let ad):
            if let ad {
                discovered.removeAll { $0.peer.id == peer.id }
                discovered.append((peer, ad))
            }
        case .peerLost(let id):
            discovered.removeAll { $0.peer.id == id || $0.peer.displayName == id }
            peers.removeAll { $0.id == id || $0.displayName == id }
            if route == .hostLive { rebalanceField() }
        case .peerStateChanged:
            peers = mesh.connectedPeers
        case .connected(let peer):
            peers = mesh.connectedPeers
            if route == .joinConnecting {
                mesh.sendControl(
                    .hello(.init(
                        app: "0.0.3",
                        peer: displayName,
                        fmtPref: AudioFormatSpec.canonical.token,
                        deviceModel: deviceProfile.model,
                        speakerQuality: deviceProfile.speakerQuality
                    )),
                    to: [peer]
                )
                startClockSyncLoop(isHost: false)
            } else if route == .hostLive {
                if !welcomedPeerIDs.contains(peer.id) {
                    welcomedPeerIDs.insert(peer.id)
                    sendWelcome(to: peer)
                    broadcastRoster()
                    rebalanceField()
                    broadcastPlaylist()
                    if isStreaming && !isStreamPaused {
                        sendStreamStart(to: [peer])
                    }
                    Haptics.light()
                }
            }
        case .disconnected:
            peers = mesh.connectedPeers
            if route == .joinLive || route == .joinConnecting || route == .joinCalibrate {
                lastError = AppError.hostGone.errorDescription
                teardownAll()
                route = .joinBrowse
                startBrowsing()
                Haptics.warning()
            } else if route == .hostLive {
                welcomedPeerIDs = Set(peers.map(\.id))
                broadcastRoster()
                rebalanceField()
            }
        case .control(let message, let from):
            handleControl(message, from: from)
        case .audio(let packet, _):
            if (route == .joinLive || route == .joinCalibrate) && !isMuted {
                playback.enqueue(packet: packet)
            }
        case .error(let error):
            lastError = Self.friendlyErrorMessage(error)
        }
    }

    private func handleControl(_ message: ControlMessage, from: String) {
        switch message {
        case .hello:
            if route == .hostLive,
               let peer = peers.first(where: { $0.displayName == from || $0.id == from }),
               !welcomedPeerIDs.contains(peer.id) {
                welcomedPeerIDs.insert(peer.id)
                sendWelcome(to: peer)
                broadcastRoster()
                rebalanceField()
                broadcastPlaylist()
                if isStreaming && !isStreamPaused {
                    sendStreamStart(to: [peer])
                }
            }
        case .welcome(let payload):
            sessionTitle = payload.title
            if let mode = SessionMode(rawValue: payload.mode) {
                sessionMode = mode.isSchwarm ? .schwarm : mode
            }
            enterJoinCalibrate()
            startClockSyncLoop(isHost: false)
        case .streamStart:
            beginJoinPlayback()
        case .streamStop(let reason):
            playback.stop()
            isStreaming = false
            isStreamPaused = (reason == "pause")
        case .reject(let code):
            lastError = (code == .full ? AppError.sessionFull : AppError.protocolMismatch).errorDescription
            teardownAll()
            route = .joinBrowse
            startBrowsing()
            Haptics.warning()
        case .goodbye:
            if route == .joinLive || route == .joinConnecting || route == .joinCalibrate {
                lastError = AppError.hostGone.errorDescription
                teardownAll()
                route = .joinBrowse
                startBrowsing()
                Haptics.warning()
            }
        case .ping(let t):
            if let peer = peers.first(where: { $0.displayName == from || $0.id == from }) {
                mesh.sendControl(.pong(t: t), to: [peer])
            } else {
                mesh.sendControl(.pong(t: t), to: nil)
            }
        case .pong(let t):
            guard pendingPingT == nil || pendingPingT == t else { return }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let rtt = Int(max(0, now - t))
            lastRTT = rtt
            pendingPingT = nil
            if rtt > 180 {
                linkQuality = .weak
            } else if rtt > 90 {
                linkQuality = .okay
            } else if underrunCount < 2 {
                linkQuality = .good
            }
        case .peerRoster(let roster):
            rosterNames = roster.map(\.name)
        case .clockSync(let payload):
            handleClockSync(payload, from: from)
        case .chirpSchedule(let payload):
            handleChirpSchedule(payload)
        case .chirpReport(let payload):
            if route == .hostLive {
                let delta = Double(payload.detectAtLocalMs - (hostPlayEpochMs ?? payload.detectAtLocalMs))
                chirpDistances[payload.peerId] = ChirpCalibrator.distanceMeters(deltaMs: abs(delta) > 80 ? 12 : 6)
                rebalanceField()
            }
        case .fieldMap(let payload):
            applyFieldMap(payload)
        case .roleAssign(let payload):
            if payload.peerId == localPeerKey || payload.peerId == displayName {
                myRole = SpeakerRole(rawValue: payload.role) ?? .mid
                playback.speakerRole = myRole
            }
        case .playlist(let payload):
            let tracks = payload.tracks.map {
                PlaylistTrack(id: $0.id, title: $0.title, path: nil, votes: $0.votes)
            }
            playlist.replace(with: tracks, current: payload.currentId)
            syncPlaylistUI()
        case .vote(let payload):
            if route == .hostLive {
                playlist.vote(trackID: payload.trackId, from: payload.peerId)
                syncPlaylistUI()
                broadcastPlaylist()
            }
        case .lightCue(let payload):
            let localAt = clock.localFromHostMs(payload.atHostMs)
            let delay = Double(localAt - ClockSync.nowMs()) / 1000.0
            let apply = { [weak self] in
                self?.lightshow.applyCue(intensity: payload.intensity, colorHue: payload.hue)
                self?.lightFlash = self?.lightshow.screenFlash ?? 0
            }
            if delay > 0.02 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: apply)
            } else {
                apply()
            }
        case .playSchedule(let payload):
            hostPlayEpochMs = payload.startHostMs
            let localAt = clock.localFromHostMs(payload.startHostMs)
            let delay = Double(localAt - ClockSync.nowMs()) / 1000.0
            if delay > 0 {
                calibrateStatus = String(localized: "calibrate.armed")
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    beginJoinPlayback()
                }
            } else {
                beginJoinPlayback()
            }
        case .calibrateDone:
            if route == .joinCalibrate {
                calibrateProgress = 1
                calibrateStatus = String(localized: "calibrate.done")
            }
        }
    }

    private func sendWelcome(to peer: MeshPeer) {
        guard let ad = activeAdvertisement else { return }
        mesh.sendControl(
            .welcome(.init(
                sessionId: ad.sessionID,
                fmt: ad.formatToken,
                mode: ad.mode.rawValue,
                title: ad.title,
                serverTimeMs: ClockSync.nowMs()
            )),
            to: [peer]
        )
    }

    private func sendStreamStart(to peers: [MeshPeer]? = nil) {
        mesh.sendControl(
            .streamStart(.init(
                epochMs: Int64(Date().timeIntervalSince1970 * 1000),
                fmt: AudioFormatSpec.canonical.token,
                frameMs: Int(AudioFormatSpec.canonical.frameDurationMs)
            )),
            to: peers
        )
    }

    private func broadcastRoster() {
        let roster = mesh.connectedPeers.map {
            ControlMessage.RosterPeer(name: $0.displayName, id: $0.id)
        }
        mesh.sendControl(.peerRoster(peers: roster), to: nil)
        rosterNames = roster.map(\.name)
    }

    private func beginJoinPlayback() {
        guard route != .joinLive else {
            isStreaming = true
            isStreamPaused = false
            return
        }
        do {
            try sessionConfig.configure(for: sessionMode, role: .join)
            try playback.prepare(targetFrames: sessionMode.jitterTargetFrames)
            playback.speakerRole = myRole
            applyJoinVolume()
            isStreaming = true
            isStreamPaused = false
            sessionActive = true
            underrunCount = 0
            linkQuality = .good
            sessionStartedAt = Date()
            holdIdleTimer(true)
            mesh.stopBrowsing()
            joinTimeoutTask?.cancel()
            joinTimeoutTask = nil
            chirp.stop()
            startPingLoop()
            startElapsedTick()
            route = .joinLive
            Haptics.success()
        } catch {
            lastError = error.localizedDescription
            teardownAll()
            route = .joinBrowse
            startBrowsing()
            Haptics.warning()
        }
    }

    private func applyJoinVolume() {
        playback.outputVolume = isMuted ? 0 : joinVolume
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.route == .hostLive || self.route == .joinLive else { return }
                let t = Int64(Date().timeIntervalSince1970 * 1000)
                self.pendingPingT = t
                self.mesh.sendControl(.ping(t: t), to: nil)
            }
        }
    }

    private func startElapsedTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.lightFlash = self.lightshow.screenFlash
                self.audioLevel = self.audioLevel
            }
        }
    }

    private func scheduleQualityRecovery() {
        qualityRecoveryTask?.cancel()
        qualityRecoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.underrunCount > 0 {
                self.underrunCount = max(0, self.underrunCount - 2)
            }
            if self.underrunCount == 0 {
                self.linkQuality = .good
            } else if self.underrunCount <= 3 {
                self.linkQuality = .okay
            }
        }
    }

    private func requestMicrophonePermission() async throws {
        let session = AVAudioSession.sharedInstance()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await AVAudioApplication.requestRecordPermission()
        } else {
            granted = await withCheckedContinuation { cont in
                session.requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        if !granted {
            throw AppError.permissionDenied(.microphone)
        }
    }

    private func observeAudioInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            break
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            guard options.contains(.shouldResume) else { return }
            do {
                if route == .hostLive {
                    try sessionConfig.configure(for: sessionMode, role: .host)
                    if !isStreamPaused {
                        switch hostSource {
                        case .microphone: try capture.start(source: .microphone)
                        case .file(let url): try capture.start(source: .file(url))
                        }
                        capture.monitorMuted = hostMonitorMuted
                        isStreaming = true
                    }
                } else if route == .joinLive {
                    try sessionConfig.configure(for: sessionMode, role: .join)
                    try playback.prepare(targetFrames: sessionMode.jitterTargetFrames)
                    playback.speakerRole = myRole
                    applyJoinVolume()
                    isStreaming = true
                }
            } catch {
                lastError = error.localizedDescription
            }
        @unknown default:
            break
        }
    }

    private func holdIdleTimer(_ hold: Bool) {
        if hold {
            guard !idleTimerHeld else { return }
            IdleTimerGuard.pushActive()
            idleTimerHeld = true
        } else if idleTimerHeld {
            IdleTimerGuard.popActive()
            idleTimerHeld = false
        }
    }

    private func teardownAll() {
        joinTimeoutTask?.cancel()
        joinTimeoutTask = nil
        pingTask?.cancel()
        pingTask = nil
        qualityRecoveryTask?.cancel()
        qualityRecoveryTask = nil
        tickTask?.cancel()
        tickTask = nil
        clockSyncTask?.cancel()
        clockSyncTask = nil
        capture.stop()
        playback.stop()
        chirp.stop()
        lightshow.stop()
        clock.reset()
        mesh.disconnect()
        sessionConfig.deactivate()
        holdIdleTimer(false)
        sessionActive = false
        isStreaming = false
        isStreamPaused = false
        isMuted = false
        peers = []
        discovered = []
        rosterNames = []
        audioLevel = 0
        activeAdvertisement = nil
        underrunCount = 0
        linkQuality = .good
        welcomedPeerIDs.removeAll()
        pendingPingT = nil
        lastRTT = nil
        sessionStartedAt = nil
        fieldMap = .empty
        myRole = .mid
        playback.speakerRole = .mid
        calibrateProgress = 0
        calibrateStatus = ""
        chirpDistances.removeAll()
        lightFlash = 0
        dragProgress = 0
        proximityReady = false
        hostPlayEpochMs = nil
        playlistTracks = []
        currentTrackID = nil
    }


    private static func friendlyErrorMessage(_ error: AppError) -> String? {
        let raw = error.errorDescription ?? ""
        let nsHints = ["NSNetServicesErrorDomain", "-72008", "Bonjour"]
        if nsHints.contains(where: { raw.contains($0) }) {
            if LiveContainerRuntime.isActive {
                return String(localized: "error.bonjour.livecontainer")
            }
            return String(localized: "error.bonjour.localNetwork")
        }
        return error.errorDescription
    }

    // MARK: Schwarm helpers

    private func enterJoinCalibrate() {
        route = .joinCalibrate
        calibrateProgress = 0.1
        calibrateStatus = String(localized: "calibrate.syncing")
        Haptics.light()
    }

    private func runHostCalibration() async {
        chirpRound += 1
        let playAt = ClockSync.nowMs() + 600
        hostPlayEpochMs = playAt
        mesh.sendControl(
            .chirpSchedule(.init(
                hostPlayAtMs: playAt,
                frequencyHz: 18_500,
                durationMs: 90,
                round: chirpRound
            )),
            to: nil
        )
        do {
            try chirp.prepare(frequencyHz: 18_500)
            chirp.playChirp(durationMs: 90, atHostMs: playAt, clock: clock)
        } catch {
            lastError = error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        rebalanceField()
        for peer in peers {
            mesh.sendControl(.calibrateDone(.init(peerId: peer.id, ok: true)), to: [peer])
        }
        chirp.stop()
    }

    private func beginHostStreamScheduled() {
        let startAt = ClockSync.nowMs() + 700
        hostPlayEpochMs = startAt
        if let current = playlist.current {
            mesh.sendControl(.playSchedule(.init(trackId: current.id, startHostMs: startAt)), to: nil)
        }
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            capture.setPaused(false)
            isStreamPaused = false
            isStreaming = true
            sendStreamStart()
            Haptics.success()
        }
    }

    private func rebalanceField() {
        let peerTuples = mesh.connectedPeers.map { (id: $0.id, name: $0.displayName) }
        fieldMap = FieldBalancer.rebalance(
            peers: peerTuples,
            hostID: localPeerKey,
            hostName: displayName,
            distances: chirpDistances,
            previous: fieldMap
        )
        broadcastFieldMap()
        if let mine = fieldMap.seats.first(where: { $0.id == localPeerKey }) {
            myRole = mine.role
            playback.speakerRole = myRole
        }
    }

    private func broadcastFieldMap() {
        let payload = ControlMessage.FieldMapPayload(
            version: fieldMap.version,
            seats: fieldMap.seats.map {
                .init(id: $0.id, name: $0.name, role: $0.role.rawValue, angleDeg: $0.angleDeg, distanceM: $0.distanceM)
            }
        )
        mesh.sendControl(.fieldMap(payload), to: nil)
        for seat in fieldMap.seats where seat.id != localPeerKey {
            if let peer = peers.first(where: { $0.id == seat.id || $0.displayName == seat.name }) {
                mesh.sendControl(
                    .roleAssign(.init(
                        peerId: seat.id,
                        role: seat.role.rawValue,
                        angleDeg: seat.angleDeg,
                        distanceM: seat.distanceM
                    )),
                    to: [peer]
                )
            }
        }
    }

    private func applyFieldMap(_ payload: ControlMessage.FieldMapPayload) {
        fieldMap = FieldMap(
            seats: payload.seats.map {
                FieldSeat(
                    id: $0.id,
                    name: $0.name,
                    role: SpeakerRole(rawValue: $0.role) ?? .mid,
                    angleDeg: $0.angleDeg,
                    distanceM: $0.distanceM
                )
            },
            version: payload.version
        )
        if let mine = fieldMap.seats.first(where: { $0.id == localPeerKey || $0.name == displayName }) {
            myRole = mine.role
            playback.speakerRole = myRole
        }
        rosterNames = fieldMap.seats.map(\.name)
        calibrateProgress = max(calibrateProgress, 0.9)
        calibrateStatus = String(localized: "calibrate.placed")
    }

    private func handleClockSync(_ payload: ControlMessage.ClockSyncPayload, from: String) {
        if route == .hostLive {
            let t1 = ClockSync.nowMs()
            let t2 = ClockSync.nowMs()
            let reply = ControlMessage.clockSync(.init(t0: payload.t0, t1: t1, t2: t2))
            if let peer = peers.first(where: { $0.displayName == from || $0.id == from }) {
                mesh.sendControl(reply, to: [peer])
            } else {
                mesh.sendControl(reply, to: nil)
            }
        } else if let t1 = payload.t1, let t2 = payload.t2 {
            let t3 = ClockSync.nowMs()
            clock.recordSample(t0: payload.t0, t1: t1, t2: t2, t3: t3)
            lastRTT = Int(clock.lastRTTMs)
        }
    }

    private func handleChirpSchedule(_ payload: ControlMessage.ChirpSchedulePayload) {
        calibrateStatus = String(localized: "calibrate.listening")
        calibrateProgress = 0.45
        do {
            try chirp.prepare(frequencyHz: payload.frequencyHz)
            chirp.armDetection { [weak self] detectMs in
                guard let self else { return }
                self.mesh.sendControl(
                    .chirpReport(.init(
                        detectAtLocalMs: detectMs,
                        round: payload.round,
                        peerId: self.localPeerKey
                    )),
                    to: nil
                )
                self.calibrateProgress = 0.8
            }
            chirp.playChirp(
                durationMs: payload.durationMs,
                atHostMs: payload.hostPlayAtMs,
                clock: clock
            )
        } catch {
            calibrateStatus = error.localizedDescription
        }
    }

    private func broadcastPlaylist() {
        let snap = playlist.snapshotPayload()
        mesh.sendControl(
            .playlist(.init(
                currentId: snap.currentID,
                tracks: snap.tracks.map { .init(id: $0.id, title: $0.title, votes: $0.votes) }
            )),
            to: nil
        )
    }

    private func syncPlaylistUI() {
        playlistTracks = playlist.ranked
        currentTrackID = playlist.currentID
    }

    private func maybeBroadcastLightCue(level: Float) {
        guard lightshowEnabled, level > 0.35 else { return }
        let now = ClockSync.nowMs()
        guard now - lastLightCueMs > 320 else { return }
        lastLightCueMs = now
        mesh.sendControl(
            .lightCue(.init(atHostMs: now + 40, intensity: min(1, level * 1.4), hue: Float(lightshow.beatPhase))),
            to: nil
        )
    }

    private func startClockSyncLoop(isHost: Bool) {
        clockSyncTask?.cancel()
        guard !isHost else { return }
        clockSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let t0 = ClockSync.nowMs()
                self.mesh.sendControl(.clockSync(.init(t0: t0, t1: nil, t2: nil)), to: nil)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if self.route != .joinCalibrate && self.route != .joinLive && self.route != .joinConnecting {
                    return
                }
            }
        }
    }
}
