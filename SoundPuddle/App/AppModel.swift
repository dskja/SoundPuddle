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

    var diagnosticsLine: String {
        let lc = isLiveContainer ? "LC" : "native"
        return "\(lc) · peers \(peers.count)/7 · underrun \(underrunCount) · \(linkQuality.rawValue)"
    }

    private let mesh: any MeshTransporting
    private let capture = AudioCaptureEngine()
    private let playback = AudioPlaybackEngine()
    private let sessionConfig = AudioSessionConfigurator()
    private let networkPrimer = LocalNetworkPrimer()
    private var eventTask: Task<Void, Never>?
    private var joinTimeoutTask: Task<Void, Never>?
    private var qualityRecoveryTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var underrunCount = 0
    private var activeAdvertisement: SessionAdvertisement?
    private var sessionActive = false

    init(mesh: (any MeshTransporting)? = nil) {
        self.mesh = mesh ?? MultipeerMeshTransport()
        capture.onFrame = { [weak self] packet in
            Task { @MainActor in self?.mesh.sendAudio(packet, to: nil) }
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
        listen()
        networkPrimer.prime()
    }

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
                switch hostSource {
                case .microphone:
                    try capture.start(source: .microphone)
                case .file(let url):
                    try capture.start(source: .file(url))
                }
                isStreaming = true
                sessionActive = true
                IdleTimerGuard.pushActive()
                sendStreamStart()
                startPingLoop()
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
        joinTimeoutTask?.cancel()
        joinTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.route == .joinConnecting {
                self.lastError = AppError.timeout.errorDescription
                self.route = .joinBrowse
                Haptics.warning()
            }
        }
    }

    func leaveSession() {
        mesh.sendControl(.goodbye(reason: "leave"), to: nil)
        teardownAll()
        route = .home
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if sessionActive { IdleTimerGuard.pushActive() }
            networkPrimer.prime()
        case .inactive, .background:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Internals

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
            joinTimeoutTask?.cancel()
            if route == .joinConnecting {
                mesh.sendControl(
                    .hello(.init(
                        app: "1.1.0",
                        peer: displayName,
                        fmtPref: AudioFormatSpec.canonical.token
                    )),
                    to: [peer]
                )
            } else if route == .hostLive {
                sendWelcome(to: peer)
                broadcastRoster()
                if isStreaming { sendStreamStart(to: [peer]) }
                Haptics.light()
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
                broadcastRoster()
            }
        case .control(let message, let from):
            handleControl(message, from: from)
        case .audio(let packet, _):
            if route == .joinLive {
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
               let peer = peers.first(where: { $0.displayName == from || $0.id == from }) {
                sendWelcome(to: peer)
                if isStreaming { sendStreamStart(to: [peer]) }
            }
        case .welcome(let payload):
            sessionTitle = payload.title
            if let mode = SessionMode(rawValue: payload.mode) {
                sessionMode = mode
            }
        case .streamStart:
            beginJoinPlayback()
        case .streamStop:
            playback.stop()
            isStreaming = false
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
            mesh.sendControl(.pong(t: t), to: nil)
        case .pong(let t):
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let rtt = max(0, now - t)
            if rtt > 180 {
                linkQuality = .weak
            } else if rtt > 90 {
                linkQuality = .okay
            } else if underrunCount < 2 {
                linkQuality = .good
            }
        case .peerRoster:
            break
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
    }

    private func beginJoinPlayback() {
        do {
            try sessionConfig.configure(for: sessionMode, role: .join)
            try playback.prepare(targetFrames: sessionMode.jitterTargetFrames)
            isStreaming = true
            sessionActive = true
            underrunCount = 0
            linkQuality = .good
            IdleTimerGuard.pushActive()
            startPingLoop()
            route = .joinLive
            Haptics.success()
        } catch {
            lastError = error.localizedDescription
            route = .joinBrowse
            Haptics.warning()
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.route == .hostLive || self.route == .joinLive else { return }
                let t = Int64(Date().timeIntervalSince1970 * 1000)
                self.mesh.sendControl(.ping(t: t), to: nil)
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

    /// Tear down audio + mesh. Keep a single long-lived event listener.
    private func teardownAll() {
        joinTimeoutTask?.cancel()
        joinTimeoutTask = nil
        pingTask?.cancel()
        pingTask = nil
        qualityRecoveryTask?.cancel()
        qualityRecoveryTask = nil
        capture.stop()
        playback.stop()
        mesh.disconnect()
        sessionConfig.deactivate()
        if sessionActive {
            IdleTimerGuard.popActive()
        }
        sessionActive = false
        isStreaming = false
        peers = []
        discovered = []
        audioLevel = 0
        activeAdvertisement = nil
        underrunCount = 0
        linkQuality = .good
    }

    var peerCapWarning: Bool { peers.count >= 6 }
}
