import SwiftUI

enum PermissionPrompt {
    static func hostMessage() -> String {
        String(localized: "permission.host.body")
    }

    static func joinMessage() -> String {
        String(localized: "permission.join.body")
    }
}
