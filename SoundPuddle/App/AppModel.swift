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
                lastError: String = error.localizedDescription
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
                lastError: String = error.localizedDescription
            }
        }
        Haptics.success()
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
        sessionMode = advertisement.mode.isSchwarm ? .schwarm : advertisement.mode
        route = .joinConnecting
        mesh.invite(peer)
        joinTime