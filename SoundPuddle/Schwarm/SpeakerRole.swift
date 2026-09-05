import Foundation

enum SpeakerRole: String, Codable, CaseIterable, Sendable {
    case mid
    case left
    case right
    case farLeft
    case farRight

    var displayKey: String {
        switch self {
        case .mid: return "role.mid"
        case .left: return "role.left"
        case .right: return "role.right"
        case .farLeft: return "role.farLeft"
        case .farRight: return "role.farRight"
        }
    }

    var pan: Float {
        switch self {
        case .mid: return 0
        case .left: return -0.55
        case .right: return 0.55
        case .farLeft: return -0.9
        case .farRight: return 0.9
        }
    }
}

struct FieldSeat: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var role: SpeakerRole
    var distanceMeters: Double?
    var quality: Double
}

struct FieldMap: Codable, Equatable, Sendable {
    var seats: [FieldSeat]
    var updatedAtMs: Int64
}
