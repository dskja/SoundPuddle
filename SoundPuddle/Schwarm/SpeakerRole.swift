import Foundation

/// Seat around the table / field. Host is always center (`mid`).
enum SpeakerRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case mid
    case left
    case right
    case farLeft
    case farRight

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .mid: return "role.mid"
        case .left: return "role.left"
        case .right: return "role.right"
        case .farLeft: return "role.farLeft"
        case .farRight: return "role.farRight"
        }
    }

    /// Stereo pan −1…1 for join-side fallback.
    var pan: Float {
        switch self {
        case .farLeft: return -1
        case .left: return -0.55
        case .mid: return 0
        case .right: return 0.55
        case .farRight: return 1
        }
    }

    /// Gains applied to (L, R, mid) stems when host does spatial routing.
    var stemGains: (l: Float, r: Float, mid: Float) {
        switch self {
        case .farLeft: return (1.0, 0.05, 0.15)
        case .left: return (0.85, 0.15, 0.35)
        case .mid: return (0.35, 0.35, 1.0)
        case .right: return (0.15, 0.85, 0.35)
        case .farRight: return (0.05, 1.0, 0.15)
        }
    }
}

struct FieldSeat: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var name: String
    var role: SpeakerRole
    var angleDeg: Double
    var distanceM: Double
}

struct FieldMap: Equatable, Codable, Sendable {
    var seats: [FieldSeat]
    var version: Int

    static let empty = FieldMap(seats: [], version: 0)
}
