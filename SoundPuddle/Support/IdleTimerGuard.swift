import UIKit

enum IdleTimerGuard {
    private static var depth = 0

    static func pushActive() {
        depth += 1
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    static func popActive() {
        depth = max(0, depth - 1)
        DispatchQueue.main.async {
            if depth == 0 {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}
