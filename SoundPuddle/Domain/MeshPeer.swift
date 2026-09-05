import Foundation

struct MeshPeer: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    var state: PeerConnectionState

    enum PeerConnectionState: String, Sendable {
        case discovered
        case connecting
        case connected
        case notConnected
    }
}
