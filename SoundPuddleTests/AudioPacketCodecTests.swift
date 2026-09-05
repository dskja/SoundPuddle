import XCTest
@testable import SoundPuddle

final class AudioPacketCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let pcm = Data((0..<960).flatMap { i -> [UInt8] in
            let s = Int16(i % 100)
            return [UInt8(truncatingIfNeeded: s.littleEndian), UInt8(truncatingIfNeeded: s.littleEndian >> 8)]
        })
        let packet = AudioPacketCodec.encode(seq: 42, pcm: pcm)
        let decoded = try XCTUnwrap(AudioPacketCodec.decode(packet))
        XCTAssertEqual(decoded.header.seq, 42)
        XCTAssertEqual(decoded.pcm, pcm)
    }

    func testRejectsBadMagic() {
        var packet = AudioPacketCodec.encode(seq: 1, pcm: Data(count: 960))
        packet[0] = 0
        XCTAssertNil(AudioPacketCodec.decode(packet))
    }
}
