import SwiftUI
import UIKit

enum Motion {
    static let route: Animation = .spring(response: 0.42, dampingFraction: 0.88)
    static let brand: Animation = .spring(response: 0.7, dampingFraction: 0.82)
    static let pulse: Animation = .easeInOut(duration: 1.7).repeatForever(autoreverses: true)
    static let wave: Animation = .linear(duration: 12).repeatForever(autoreverses: false)
    static let snappy: Animation = .spring(response: 0.32, dampingFraction: 0.78)

    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}
