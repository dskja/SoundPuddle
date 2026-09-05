import Foundation

enum AppError: LocalizedError, Equatable, Sendable {
    case permissionDenied(PermissionKind)
    case mesh(String)
    case audio(String)
    case sessionFull
    case protocolMismatch
    case timeout
    case hostGone
    case cancelled

    enum PermissionKind: String, Sendable {
        case localNetwork
        case microphone
        case bluetooth
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let kind):
            return String(localized: "error.permission.\(kind.rawValue)")
        case .mesh(let message):
            return message
        case .audio(let message):
            return message
        case .sessionFull:
            return String(localized: "error.sessionFull")
        case .protocolMismatch:
            return String(localized: "error.protocolMismatch")
        case .timeout:
            return String(localized: "error.timeout")
        case .hostGone:
            return String(localized: "error.hostGone")
        case .cancelled:
            return String(localized: "error.cancelled")
        }
    }
}
