import Foundation

enum MeshEvent: Sendable {
    case peerDiscovered(MeshPeer, SessionAdvertisement?)
    case peerLost(String)
    case peerStateChanged(MeshPeer)
    case connected(MeshPeer)
    case disconnected(MeshPeer)
    case control(ControlMessage, from: String)
    case audio(Data, from: String)
    case error(AppError)
}

@MainActor
protocol MeshTransporting: AnyObject {
    var connectedPeers: [MeshPeer] { get }
    var events: AsyncStream<MeshEvent> { get }
    /// Host-side `ip:port` for LiveContainer direct join. Nil for Multipeer.
    var publishedJoinAddress: String? { get }
    func startHosting(advertisement: SessionAdvertisement)
    func stopHosting()
    func startBrowsing()
    func stopBrowsing()
    func invite(_ peer: MeshPeer)
    func acceptInvitations(_ accept: Bool)
    func sendControl(_ message: ControlMessage, to peers: [MeshPeer]?)
    func sendAudio(_ packet: Data, to peers: [MeshPeer]?)
    func disconnect()
    /// Direct TCP join via `ip:port` (LiveContainer path).
    func connect(toAddress address: String)
}

extension MeshTransporting {
    var publishedJoinAddress: String? { nil }
    func connect(toAddress address: String) {}
}
