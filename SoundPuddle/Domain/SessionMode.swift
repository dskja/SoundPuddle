import Foundation

enum SessionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case party
    case tour
    case cinema

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .party: return "mode.party"
        case .tour: return "mode.tour"
        case .cinema: return "mode.cinema"
        }
    }

    var blurbKey: String {
        switch self {
        case .party: return "mode.party.blurb"
        case .tour: return "mode.tour.blurb"
        case .cinema: return "mode.cinema.blurb"
        }
    }

    var jitterTargetFrames: Int {
        switch self {
        case .party: return 3
        case .tour, .cinema: return 4
        }
    }
}
