import Foundation

enum MeshTransportFactory {
    @MainActor
    static func make() -> any MeshTransporting {
        if LiveContainerRuntime.isActive {
            return LANBonjourMeshTransport()
        }
        return MultipeerMeshTransport()
    }
}
