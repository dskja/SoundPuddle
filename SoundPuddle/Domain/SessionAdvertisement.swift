import Foundation

struct SessionAdvertisement: Equatable, Sendable {
    var protocolVersion: Int
    var title: String
    var mode: SessionMode
    var formatToken: String
    var capacity: Int
    var sessionID: String

    static let serviceType = "soundpuddle"
    static let maxTitleLength = 24
    static let maxJoiners = 7

    init(
        title: String,
        mode: SessionMode,
        sessionID: String = SessionAdvertisement.makeSessionID(),
        protocolVersion: Int = ProtocolVersion.major,
        formatToken: String = AudioFormatSpec.canonical.token,
        capacity: Int = SessionAdvertisement.maxJoiners
    ) {
        self.protocolVersion = protocolVersion
        self.title = String(title.prefix(Self.maxTitleLength))
        self.mode = mode
        self.formatToken = formatToken
        self.capacity = capacity
        self.sessionID = sessionID
    }

    var discoveryInfo: [String: String] {
        [
            "v": "\(protocolVersion)",
            "title": title,
            "mode": mode.rawValue,
            "fmt": formatToken,
            "cap": "\(capacity)",
            "id": sessionID
        ]
    }

    static func from(discoveryInfo info: [String: String]?) -> SessionAdvertisement? {
        guard
            let info,
            let v = info["v"], let major = Int(v),
            let title = info["title"], !title.isEmpty,
            let modeRaw = info["mode"], let mode = SessionMode(rawValue: modeRaw),
            let fmt = info["fmt"],
            let capRaw = info["cap"], let cap = Int(capRaw),
            let id = info["id"]
        else { return nil }

        return SessionAdvertisement(
            title: title,
            mode: mode,
            sessionID: id,
            protocolVersion: major,
            formatToken: fmt,
            capacity: cap
        )
    }

    static func makeSessionID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }
}
