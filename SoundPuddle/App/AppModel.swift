import Foundation
import Observation
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

    private let mesh: any MeshTransporting
    private let capture = AudioCaptureEngine()
    private let playback = AudioPlaybackEngine()
    private let sessionConfig = AudioSessionConfigurator()
    private var eventTask: Task<Void, Never>?
    private var underrunCount = 0
    private var activeAdvertisement: SessionAdvertisement?

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
            }
        }
        listen()
    }

    func openHost() {
        showPermissionHint = true
        route = .hostSetup
    }

    func openJoin() {
        showPermissionHint = true
        route = .joinBrowse
        startBrowsing()
    }

    func goHome() {
        teardownAll()
        route = .home
        lastError = nil
    }

    func startHosting() {
        let trimmed = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? String(localized: "host.defaultTitle") : trimmed
        sessionTitle = title
        let ad = SessionAdvertisement(title: title, mode: sessionMode)
        activeAdvertisement = ad

        do {
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
            sendStreamStart()
            route = .hostLive
        } catch {
            lastError = error.localizedDescription
            teardownAll()
            route = .hostSetup
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
        sessionTitle = advertisement.title
        sessionMode = advertisement.mode
        route = .joinConnecting
        mesh.invite(peer)
        Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if route == .joinConnecting {
                lastError = AppError.timeout.errorDescription
                route = .joinBrowse
            }
        }
    }

    func leaveSession() {
        mesh.sendControl(.goodbye(reason: "leave"), to: nil)
        teardownAll()
        route = .home
    }

    private func listen() {
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.mesh.events {
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
                        app: "1.0.0",
                        peer: UIDevice.current.name,
                        fmtPref: AudioFormatSpec.canonical.token
                    )),
                    to: [peer]
                )
            } else if route == .hostLive {
                sendWelcome(to: peer)
                broadcastRoster()
                if isStreaming { sendStreamStart(to: [peer]) }
            }
        case .disconnected:
            peers = mesh.connectedPeers
            if route == .joinLive || route == .joinConnecting {
                lastError = AppError.hostGone.errorDescription
                teardownAll()
                route = .joinBrowse
                startBrowsing()
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
        case .goodbye:
            if route == .joinLive || route == .joinConnecting {
                lastError = AppError.hostGone.errorDescription
                teardownAll()
                route = .joinBrowse
                startBrowsing()
            }
        case .ping(let t):
            mesh.sendControl(.pong(t: t), to: nil)
        case .pong, .peerRoster:
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
            underrunCount = 0
            linkQuality = .good
            route = .joinLive
        } catch {
            lastError = error.localizedDescription
            route = .joinBrowse
        }
    }

    private func teardownAll() {
        capture.stop()
        playback.stop()
        mesh.disconnect()
        sessionConfig.deactivate()
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
