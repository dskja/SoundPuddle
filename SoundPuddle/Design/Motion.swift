import SwiftUI

enum Motion {
    static let route: Animation = .easeInOut(duration: 0.35)
    static let brand: Animation = .spring(response: 0.7, dampingFraction: 0.82)
    static let pulse: Animation = .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    static let wave: Animation = .linear(duration: 14).repeatForever(autoreverses: false)

    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}
