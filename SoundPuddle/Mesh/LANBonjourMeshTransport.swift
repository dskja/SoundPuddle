import Darwin
import Foundation
import Network
import UIKit

/// LiveContainer blocks Multipeer Bonjour (`_soundpuddle`) via host allowlist (-72008).
/// This transport:
/// 1) listens on TCP and publishes `ip:port` for manual join (reliable in LiveContainer)
/// 2) optionally advertises/browses `_mqtt._tcp` (allowlisted) as a best-effort shortcut
@MainActor
final class LANBonjourMeshTransport: MeshTransporting {
    static let bonjourType = "_mqtt._tcp"
    private static let namePrefix = "SP-"
    private static let preferredPort: UInt16 = 47822
    private static let magic: [UInt8] = [0x53, 0x50, 0x4C, 0x44] // SPLD

    private enum FrameType: UInt8 {
        case hello = 1
        case control = 2
        case audio = 3
    }

    private struct PeerPipe {
        var peer: MeshPeer
        var connection: NWConnection
        var buffer = Data()
    }

    private var eventContinuation: AsyncStream<MeshEvent>.Continuation?
    private(set) lazy var events: AsyncStream<MeshEvent> = AsyncStream { continuation in
        self.eventContinuation = continuation
    }

    private(set) var connectedPeers: [MeshPeer] = []
    private(set) var publishedJoinAddress: String?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var isHosting = false
    private var autoAcceptInvitations = true
    private var hostingCapacity = SessionAdvertisement.maxJoiners
    private var activeAdvertisement: SessionAdvertisement?
    private let myDisplayName: String

    private var discovered: [String: (endpoint: NWEndpoint, advertisement: SessionAdvertisement?, name: String)] = [:]
    private var pipes: [String: PeerPipe] = [:]
    private var boundPort: UInt16?

    init() {
        myDisplayName = Self.sanitizedDisplayName()
    }

    private static func sanitizedDisplayName() -> String {
        let stored = UserDefaults.standard.string(forKey: "displayName")
        let raw = stored ?? UIDevice.current.name
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(cleaned.prefix(20))
        return clipped.isEmpty ? "iPhone" : clipped
    }

    // MARK: - MeshTransporting

    func startHosting(advertisement: SessionAdvertisement) {
        isHosting = true
        activeAdvertisement = advertisement
        hostingCapacity = advertisement.capacity
        publishedJoinAddress = nil
        boundPort = nil
        stopBrowsing()
        startListener(advertisement: advertisement)
    }

    func stopHosting() {
        isHosting = false
        activeAdvertisement = nil
        publishedJoinAddress = nil
        boundPort = nil
        listener?.cancel()
        listener = nil
    }

    func startBrowsing() {
        isHosting = false
        stopHosting()
        startBrowser()
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        for id in Array(discovered.keys) {
            emit(.peerLost(id))
        }
        discovered.removeAll()
    }

    func invite(_ peer: MeshPeer) {
        // Prefer direct TCP when the peer id encodes host:port (manual join).
        if let direct = Self.parseAddress(peer.id) ?? Self.parseAddress(peer.displayName) {
            connect(toAddress: "\(direct.host):\(direct.port)", displayName: peer.displayName)
            return
        }
        guard let entry = discovered[peer.id] else {
            emit(.error(.mesh(String(localized: "error.peerMissing"))))
            return
        }
        emit(.peerStateChanged(MeshPeer(id: peer.id, displayName: peer.displayName, state: .connecting)))
        let connection = NWConnection(to: entry.endpoint, using: Self.tcpParameters())
        attach(connection: connection, peerID: peer.id, displayName: peer.displayName)
        connection.start(queue: .main)
    }

    func acceptInvitations(_ accept: Bool) {
        autoAcceptInvitations = accept
    }

    func sendControl(_ message: ControlMessage, to peers: [MeshPeer]?) {
        guard let data = try? ControlCodec.encode(message) else { return }
        broadcast(frame: .control, payload: data, to: peers)
    }

    func sendAudio(_ packet: Data, to peers: [MeshPeer]?) {
        broadcast(frame: .audio, payload: packet, to: peers)
    }

    func disconnect() {
        stopHosting()
        stopBrowsing()
        for key in Array(pipes.keys) {
            pipes[key]?.connection.cancel()
        }
        pipes.removeAll()
        connectedPeers = []
    }

    func connect(toAddress address: String) {
        connect(toAddress: address, displayName: address)
    }

    private func connect(toAddress address: String, displayName: String) {
        guard let parsed = Self.parseAddress(address) else {
            emit(.error(.mesh(String(localized: "error.joinCodeInvalid"))))
            return
        }
        let peerID = "\(parsed.host):\(parsed.port)"
        emit(.peerStateChanged(MeshPeer(id: peerID, displayName: displayName, state: .connecting)))
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(parsed.host),
            port: NWEndpoint.Port(rawValue: parsed.port)!
        )
        let connection = NWConnection(to: endpoint, using: Self.tcpParameters())
        attach(connection: connection, peerID: peerID, displayName: displayName)
        connection.start(queue: .main)
    }

    // MARK: - Listener / Browser

    private func startListener(advertisement: SessionAdvertisement) {
        listener?.cancel()
        let parameters = Self.tcpParameters()
        do {
            let listener: NWListener
            if let preferred = NWEndpoint.Port(rawValue: Self.preferredPort) {
                do {
                    listener = try NWListener(using: parameters, on: preferred)
                } catch {
                    listener = try NWListener(using: parameters)
                }
            } else {
                listener = try NWListener(using: parameters)
            }

            listener.service = NWListener.Service(
                name: Self.namePrefix + advertisement.sessionID,
                type: Self.bonjourType,
                txtRecord: Self.makeTXTRecord(from: advertisement)
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = self.listener?.port?.rawValue {
                            self.boundPort = port
                            self.refreshPublishedAddress()
                        }
                    case .failed(let error):
                        self.emit(.error(.mesh(Self.friendlyError(error))))
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleInbound(connection)
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            emit(.error(.mesh(Self.friendlyError(error))))
        }
    }

    private func refreshPublishedAddress() {
        guard let port = boundPort, let ip = Self.primaryIPv4() else {
            publishedJoinAddress = nil
            return
        }
        publishedJoinAddress = "\(ip):\(port)"
    }

    private func startBrowser() {
        browser?.cancel()
        // Use generic parameters for browsing — TCP-only parameters often miss Bonjour results.
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.bonjourType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed(let error) = state {
                    // Bonjour browse is best-effort in LiveContainer; manual IP join remains available.
                    self?.emit(.error(.mesh(Self.friendlyError(error))))
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.applyBrowseResults(results)
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func applyBrowseResults(_ results: Set<NWBrowser.Result>) {
        var seen = Set<String>()
        for result in results {
            guard case let .service(name: name, type: _, domain: _, interface: _) = result.endpoint else { continue }
            guard name.hasPrefix(Self.namePrefix) else { continue }
            let id = name
            seen.insert(id)
            let advertisement = Self.advertisement(from: result) ?? advertisementFallback(name: name)
            let display = advertisement?.title ?? String(name.dropFirst(Self.namePrefix.count))
            let isNew = discovered[id] == nil
            discovered[id] = (result.endpoint, advertisement, display)
            if isNew {
                emit(.peerDiscovered(MeshPeer(id: id, displayName: display, state: .discovered), advertisement))
            }
        }
        for id in Set(discovered.keys).subtracting(seen) {
            discovered.removeValue(forKey: id)
            emit(.peerLost(id))
        }
    }

    private func advertisementFallback(name: String) -> SessionAdvertisement {
        SessionAdvertisement(
            title: String(name.dropFirst(Self.namePrefix.count)),
            mode: .schwarm,
            sessionID: String(name.dropFirst(Self.namePrefix.count))
        )
    }

    private func handleInbound(_ connection: NWConnection) {
        guard isHosting else {
            connection.cancel()
            return
        }
        guard connectedPeers.count < hostingCapacity else {
            emit(.error(.sessionFull))
            connection.cancel()
            return
        }
        guard autoAcceptInvitations else {
            connection.cancel()
            return
        }
        let tempID = "pending-\(UUID().uuidString.prefix(8))"
        attach(connection: connection, peerID: tempID, displayName: "Guest")
        connection.start(queue: .main)
    }

    private func attach(connection: NWConnection, peerID: String, displayName: String) {
        pipes[peerID] = PeerPipe(
            peer: MeshPeer(id: peerID, displayName: displayName, state: .connecting),
            connection: connection
        )
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(peerID: peerID, state: state)
            }
        }
        receiveMore(peerID: peerID)
    }

    private func handleConnectionState(peerID: String, state: NWConnection.State) {
        switch state {
        case .ready:
            sendHello(to: peerID)
        case .failed(let error):
            emit(.error(.mesh(Self.friendlyError(error))))
            removePeer(peerID, announce: true)
        case .cancelled:
            removePeer(peerID, announce: true)
        default:
            break
        }
    }

    private func sendHello(to peerID: String) {
        let body: [String: String] = [
            "name": myDisplayName,
            "role": isHosting ? "host" : "join"
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
        send(frame: .hello, payload: payload, toPeerID: peerID)
    }

    // MARK: - Framing

    private func broadcast(frame: FrameType, payload: Data, to peers: [MeshPeer]?) {
        let keys: [String]
        if let peers {
            let ids = Set(peers.map(\.id))
            let names = Set(peers.map(\.displayName))
            keys = pipes.compactMap { key, pipe in
                (ids.contains(pipe.peer.id) || names.contains(pipe.peer.displayName)) ? key : nil
            }
        } else {
            keys = Array(pipes.keys)
        }
        for key in keys {
            send(frame: frame, payload: payload, toPeerID: key)
        }
    }

    private func send(frame: FrameType, payload: Data, toPeerID: String) {
        guard let pipe = pipes[toPeerID] else { return }
        var packet = Data(Self.magic)
        packet.append(frame.rawValue)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)
        pipe.connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    private func receiveMore(peerID: String) {
        guard let connection = pipes[peerID]?.connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.emit(.error(.mesh(Self.friendlyError(error))))
                    self.removePeer(peerID, announce: true)
                    return
                }
                if let data, !data.isEmpty {
                    self.pipes[peerID]?.buffer.append(data)
                    self.drain(peerID: peerID)
                }
                if isComplete {
                    self.removePeer(peerID, announce: true)
                    return
                }
                self.receiveMore(peerID: peerID)
            }
        }
    }

    private func drain(peerID: String) {
        while true {
            guard var pipe = pipes[peerID] else { return }
            var buffer = pipe.buffer
            guard buffer.count >= 9 else { return }
            if Array(buffer.prefix(4)) != Self.magic {
                buffer.removeFirst()
                pipe.buffer = buffer
                pipes[peerID] = pipe
                continue
            }
            let typeRaw = buffer[4]
            let length = Int(buffer.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard length >= 0, length < 512_000 else {
                buffer.removeFirst(5)
                pipe.buffer = buffer
                pipes[peerID] = pipe
                continue
            }
            guard buffer.count >= 9 + length else { return }
            let payload = buffer.subdata(in: 9..<(9 + length))
            buffer.removeSubrange(0..<(9 + length))
            pipe.buffer = buffer
            pipes[peerID] = pipe
            handleFrame(peerID: peerID, typeRaw: typeRaw, payload: payload)
        }
    }

    private func handleFrame(peerID: String, typeRaw: UInt8, payload: Data) {
        guard let type = FrameType(rawValue: typeRaw) else { return }
        switch type {
        case .hello:
            handleHello(peerID: peerID, payload: payload)
        case .control:
            let from = pipes[peerID]?.peer.displayName ?? peerID
            if let message = try? ControlCodec.decode(payload) {
                emit(.control(message, from: from))
            }
        case .audio:
            let from = pipes[peerID]?.peer.displayName ?? peerID
            emit(.audio(payload, from: from))
        }
    }

    private func handleHello(peerID: String, payload: Data) {
        guard
            let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: String],
            let name = obj["name"], !name.isEmpty
        else { return }

        let peer = MeshPeer(id: peerID, displayName: name, state: .connected)
        if var pipe = pipes[peerID] {
            pipe.peer = peer
            pipes[peerID] = pipe
        }
        if let idx = connectedPeers.firstIndex(where: { $0.id == peerID }) {
            connectedPeers[idx] = peer
        } else {
            connectedPeers.append(peer)
        }
        emit(.peerStateChanged(peer))
        emit(.connected(peer))
    }

    private func removePeer(_ peerID: String, announce: Bool) {
        guard let pipe = pipes.removeValue(forKey: peerID) else { return }
        pipe.connection.cancel()
        let id = pipe.peer.id
        connectedPeers.removeAll { $0.id == peerID || $0.id == id }
        if announce {
            emit(.disconnected(MeshPeer(id: id, displayName: pipe.peer.displayName, state: .notConnected)))
        }
    }

    private func emit(_ event: MeshEvent) {
        eventContinuation?.yield(event)
    }

    // MARK: - Helpers

    private static func tcpParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        return parameters
    }

    private static func makeTXTRecord(from advertisement: SessionAdvertisement) -> NWTXTRecord {
        var entries: [String: String] = [:]
        for (key, value) in advertisement.discoveryInfo {
            entries[key] = String(value.prefix(90))
        }
        return NWTXTRecord(entries)
    }

    private static func advertisement(from result: NWBrowser.Result) -> SessionAdvertisement? {
        var info: [String: String] = [:]
        if case .bonjour(let record) = result.metadata {
            info = record.dictionary
        }
        return SessionAdvertisement.from(discoveryInfo: info.isEmpty ? nil : info)
    }

    private static func parseAddress(_ raw: String) -> (host: String, port: UInt16)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept "ip:port" or "SP ip:port"
        let candidate = trimmed
            .replacingOccurrences(of: "SP ", with: "")
            .replacingOccurrences(of: "sp ", with: "")
        let parts = candidate.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), port > 0 else { return nil }
        let host = String(parts[0])
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    private static func primaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("wlan") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                iface.ifa_addr,
                socklen_t(iface.ifa_addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: host)
            if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }
            if name == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }

    private static func friendlyError(_ error: Error) -> String {
        let ns = error as NSError
        let blob = "\(ns.domain) \(ns.code) \(ns.localizedDescription)"
        if blob.contains("72008")
            || ns.code == -72008
            || ns.domain.localizedCaseInsensitiveContains("NetService")
            || LiveContainerRuntime.isActive
        {
            return String(localized: "error.bonjour.livecontainer.fallback")
        }
        return ns.localizedDescription
    }
}
