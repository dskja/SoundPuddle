import Foundation

enum SessionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case schwarm
    /// Legacy aliases kept for discovery decode.
    case party
    case tour
    case cinema

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .schwarm, .party: return "mode.schwarm"
        case .tour: return "mode.tour"
        case .cinema: return "mode.cinema"
        }
    }

    var blurbKey: String {
        switch self {
        case .schwarm, .party: return "mode.schwarm.blurb"
        case .tour: return "mode.tour.blurb"
        case .cinema: return "mode.cinema.blurb"
        }
    }

    var jitterTargetFrames: Int {
        switch self {
        case .schwarm, .party: return 3
        case .tour, .cinema: return 4
        }
    }

    var isSchwarm: Bool {
        self == .schwarm || self == .party
    }
}
