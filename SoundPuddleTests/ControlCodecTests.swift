import XCTest
@testable import SoundPuddle

final class ControlCodecTests: XCTestCase {
    func testHelloRoundTrip() throws {
        let msg = ControlMessage.hello(.init(app: "1.0.0", peer: "A", fmtPref: AudioFormatSpec.canonical.token))
        let data = try ControlCodec.encode(msg)
        let decoded = try XCTUnwrap(try ControlCodec.decode(data))
        XCTAssertEqual(decoded, msg)
    }

    func testRejectRoundTrip() throws {
        let msg = ControlMessage.reject(code: .full)
        let data = try ControlCodec.encode(msg)
        let decoded = try XCTUnwrap(try ControlCodec.decode(data))
        XCTAssertEqual(decoded, msg)
    }

    func testChirpScheduleRoundTrip() throws {
        let msg = ControlMessage.chirpSchedule(.init(
            hostPlayAtMs: 123,
            frequencyHz: 18_500,
            durationMs: 90,
            round: 1
        ))
        let data = try ControlCodec.encode(msg)
        let decoded = try XCTUnwrap(try ControlCodec.decode(data))
        XCTAssertEqual(decoded, msg)
    }

    func testFieldMapRoundTrip() throws {
        let msg = ControlMessage.fieldMap(.init(
            version: 2,
            seats: [.init(id: "a", name: "A", role: "mid", angleDeg: 0, distanceM: 0)]
        ))
        let data = try ControlCodec.encode(msg)
        let decoded = try XCTUnwrap(try ControlCodec.decode(data))
        XCTAssertEqual(decoded, msg)
    }
}
