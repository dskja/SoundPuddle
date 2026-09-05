import Foundation

enum ControlMessage: Equatable, Sendable {
    case hello(HelloPayload)
    case welcome(WelcomePayload)
    case streamStart(StreamStartPayload)
    case streamStop(reason: String)
    case peerRoster(peers: [RosterPeer])
    case ping(t: Int64)
    case pong(t: Int64)
    case goodbye(reason: String)
    case reject(code: RejectCode)

    enum RejectCode: String, Codable, Sendable {
        case full
        case version
        case busy
    }

    struct HelloPayload: Codable, Equatable, Sendable {
        var app: String
        var peer: String
        var fmtPref: String
    }

    struct WelcomePayload: Codable, Equatable, Sendable {
        var sessionId: String
        var fmt: String
        var mode: String
        var title: String
        var serverTimeMs: Int64
    }

    struct StreamStartPayload: Codable, Equatable, Sendable {
        var epochMs: Int64
        var fmt: String
        var frameMs: Int
    }

    struct RosterPeer: Codable, Equatable, Sendable {
        var name: String
        var id: String
    }

    var msgType: UInt8 {
        switch self {
        case .hello: return 1
        case .welcome: return 2
        case .streamStart: return 3
        case .streamStop: return 4
        case .peerRoster: return 5
        case .ping: return 6
        case .pong: return 7
        case .goodbye: return 8
        case .reject: return 9
        }
    }
}

enum ControlCodec {
    static func encode(_ message: ControlMessage) throws -> Data {
        let payloadData: Data
        switch message {
        case .hello(let p):
            payloadData = try JSONEncoder().encode(p)
        case .welcome(let p):
            payloadData = try JSONEncoder().encode(p)
        case .streamStart(let p):
            payloadData = try JSONEncoder().encode(p)
        case .streamStop(let reason):
            payloadData = try JSONEncoder().encode(["reason": reason])
        case .peerRoster(let peers):
            struct RosterBox: Codable { var peers: [ControlMessage.RosterPeer] }
            payloadData = try JSONEncoder().encode(RosterBox(peers: peers))
        case .ping(let t), .pong(let t):
            payloadData = try JSONEncoder().encode(["t": t])
        case .goodbye(let reason):
            payloadData = try JSONEncoder().encode(["reason": reason])
        case .reject(let code):
            payloadData = try JSONEncoder().encode(["code": code.rawValue])
        }

        var data = Data(capacity: 4 + payloadData.count)
        data.append(message.msgType)
        data.append(UInt8(ProtocolVersion.major))
        var length = UInt16(payloadData.count).littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(payloadData)
        return data
    }

    static func decode(_ data: Data) throws -> ControlMessage? {
        guard data.count >= 4 else { return nil }
        let type = data[0]
        let major = data[1]
        guard major == ProtocolVersion.major else {
            throw AppError.protocolMismatch
        }
        let length = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        guard data.count >= 4 + Int(length) else { return nil }
        let payload = data.subdata(in: 4..<(4 + Int(length)))
        let decoder = JSONDecoder()

        switch type {
        case 1:
            return .hello(try decoder.decode(ControlMessage.HelloPayload.self, from: payload))
        case 2:
            return .welcome(try decoder.decode(ControlMessage.WelcomePayload.self, from: payload))
        case 3:
            return .streamStart(try decoder.decode(ControlMessage.StreamStartPayload.self, from: payload))
        case 4:
            let obj = try decoder.decode([String: String].self, from: payload)
            return .streamStop(reason: obj["reason"] ?? "unknown")
        case 5:
            struct RosterBox: Codable { var peers: [ControlMessage.RosterPeer] }
            return .peerRoster(peers: try decoder.decode(RosterBox.self, from: payload).peers)
        case 6:
            let obj = try decoder.decode([String: Int64].self, from: payload)
            return .ping(t: obj["t"] ?? 0)
        case 7:
            let obj = try decoder.decode([String: Int64].self, from: payload)
            return .pong(t: obj["t"] ?? 0)
        case 8:
            let obj = try decoder.decode([String: String].self, from: payload)
            return .goodbye(reason: obj["reason"] ?? "unknown")
        case 9:
            let obj = try decoder.decode([String: String].self, from: payload)
            let code = ControlMessage.RejectCode(rawValue: obj["code"] ?? "busy") ?? .busy
            return .reject(code: code)
        default:
            return nil
        }
    }
}
