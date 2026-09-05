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
        case joinLive
    }

    enum HostSource: Equatable {
        case microphone
        case file(URL)
    }

    // MARK: View-facing state
    var route: Route = .home
    var sessionTitle = ""
    var sessionMode: SessionMode = .party
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
        return "\(lc) · peers \(peers.count)/7 · underrun \(underrunCount) · \(linkQuality.rawValue) · rtt \(rttLabel)\(pause)"
    }

    var peerCapWarning: Bool { peers.count >= 6 }

    // MARK: Internals
    private let mesh: any MeshTransporting
    private let capture = AudioCaptureEngine()
    private let playback = AudioPlaybackEngine()
    private let sessionConfig = AudioSessionConfigurator()
    private let networkPrimer = LocalNetworkPrimer()
    private var eventTask: Task<Void, Never>?
    private var joinTimeoutTask: Task<Void, Never>?
    private var qualityRecoveryTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var underrunCount = 0
    private var activeAdvertisement: SessionAdvertisement?
    private var sessionActive = false
    private var idleTimerHeld = false
    private var welcomedPeerIDs = Set<String>()
    private var pendingPingT: Int64?
    private var interruptionObserver: NSObjectProtocol?

    init(mesh: (any MeshTransporting)? = nil) {
        self.mesh = mesh ?? MultipeerMeshTransport()
        capture.onFrame = { [weak self] packet in
            Task { @MainActor in
                guard let self, self.isStreaming, !self.isStreamPaused else { return }
                self.mesh.sendAudio(packet, to: nil)
            }
        }
        capture.onLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }
        playback.onLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
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
        networkPrimer.prime()
        route = .hostSetup
    }

    func openJoin() {
        showPermissionHint = true
        lastError = nil
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
            lastError = nil
            Haptics.light()
        } catch {
            lastError = error.localizedDescription
            Haptics.warning()
        }
    }

    // MARK: Host

    func startHosting() {
        let trimmed = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? String(localized: "host.defaultTitle") : trimmed
        sessionTitle = title
        let ad = SessionAdvertisement(title: title, mode: sessionMode)
        activeAdvertisement = ad

        Task {
            do {
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
                }
                isStreaming = true
                isStreamPaused = false
                sessionActive = true
                sessionStartedAt = Date()
                holdIdleTimer(true)
                sendStreamStart()
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

    // MARK: Join

    func startBrowsing() {
        discovered = []
        mesh.startBrowsing()
    }

    func join(peer: MeshPeer, advertisement: SessionAdvertisement) {
        if advertisement.protocolVersion != ProtocolVersion.major {
            lastError = AppError.protocolMismatch.errorDescription
            return
        }
        lastError = nil
        sessionTitle = advertisement.title
        sessionMode = advertisement.mode
        route = .joinConnecting
        mesh.invite(peer)
        // Timeout stays until joinLive — not cancelled on mere .connected
        joinTimeoutTask?.cancel()
        joinTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.route == .joinConnecting {
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
            discovered.removeAll { $0.peer.id == id }
            peers.removeAll { $0.id == id }
        case .peerStateChanged:
            peers = mesh.connectedPeers
        case .connected(let peer):
            peers = mesh.connectedPeers
            if route == .joinConnecting {
                mesh.sendControl(
                    .hello(.init(
                        app: "0.0.2",
                        peer: displayName,
                        fmtPref: AudioFormatSpec.canonical.token
                    )),
                    to: [peer]
                )
            } else if route == .hostLive {
                if !welcomedPeerIDs.contains(peer.id) {
                    welcomedPeerIDs.insert(peer.id)
                    sendWelcome(to: peer)
                    broadcastRoster()
                    if isStreaming && !isStreamPaused {
                        sendStreamStart(to: [peer])
                    }
                    Haptics.light()
                }
            }
        case .disconnected:
            peers = mesh.connectedPeers
            if route == .joinLive || route == .joinConnecting {
                lastError = AppError.hostGone.errorDescription
                teardownAll()
                route = .joinBrowse
                startBrowsing()
                Haptics.warning()
            } else if route == .hostLive {
                welcomedPeerIDs = Set(peers.map(\.id))
                broadcastRoster()
            }
        case .control(let message, let from):
            handleControl(message, from: from)
        case .audio(let packet, _):
            if route == .joinLive && !isMuted {
                playback.enqueue(packet: packet)
            }
        case .error(let error):
            lastError = error.errorDescription
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
                if isStreaming && !isStreamPaused {
                    sendStreamStart(to: [peer])
                }
            }
        case .welcome(let payload):
            sessionTitle = payload.title
            if let mode = SessionMode(rawValue: payload.mode) {
                sessionMode = mode
            }
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
            if route == .joinLive || route == .joinConnecting {
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
                serverTimeMs: Int64(Date().timeIntervalSince1970 * 1000)
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
        guard route != .joinLive else { return }
        do {
            try sessionConfig.configure(for: sessionMode, role: .join)
            try playback.prepare(targetFrames: sessionMode.jitterTargetFrames)
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
        capture.stop()
        playback.stop()
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
    }
}
