import Foundation

/// Detects LiveContainer guest execution and exposes runtime adaptations.
enum LiveContainerRuntime {
    static var isActive: Bool {
        if let flag = UserDefaults.standard.object(forKey: "LCForceGuestMode") as? Bool {
            return flag
        }
        let path = Bundle.main.bundlePath
        let markers = [
            "LiveContainer",
            "livecontainer",
            "/Documents/Applications/",
            "com.kdt.livecontainer"
        ]
        if markers.contains(where: { path.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        let env = ProcessInfo.processInfo.environment
        if env["LC_HOME"] != nil || env["LIVECONTAINER"] != nil {
            return true
        }
        if NSHomeDirectory().localizedCaseInsensitiveContains("LiveContainer") {
            return true
        }
        return false
    }

    static var preferredEncryption: EncryptionPreference {
        isActive ? .optional : .required
    }

    enum EncryptionPreference {
        case required
        case optional
        case none
    }

    static var hostTipKey: String {
        isActive ? "livecontainer.tip.host" : "permission.host.body"
    }

    static var joinTipKey: String {
        isActive ? "livecontainer.tip.join" : "permission.join.body"
    }
}
