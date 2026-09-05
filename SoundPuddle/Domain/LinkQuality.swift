import Foundation

enum LinkQuality: String, Sendable {
    case good
    case okay
    case weak

    var titleKey: String {
        switch self {
        case .good: return "link.good"
        case .okay: return "link.okay"
        case .weak: return "link.weak"
        }
    }
}
