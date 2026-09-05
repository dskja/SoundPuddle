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
}
