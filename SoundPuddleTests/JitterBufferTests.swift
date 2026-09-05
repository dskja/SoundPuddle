import XCTest
@testable import SoundPuddle

final class JitterBufferTests: XCTestCase {
    func testOrdersAndDropsLate() {
        let jitter = JitterBuffer(targetFrames: 2)
        jitter.push(seq: 2, pcm: Data([2]))
        jitter.push(seq: 1, pcm: Data([1]))
        XCTAssertNil(jitter.pop()) // not started until target
        jitter.push(seq: 3, pcm: Data([3]))
        // after start, expect seq 1 first if expected seeded at 2? first push sets expected=2
        // Push order: expected becomes 2, then 1 is late drop, then 3 buffered
        // With only 2 and 3, count=2 -> start, pop expects 2
        let first = jitter.pop()
        XCTAssertEqual(first, Data([2]))
    }
}
