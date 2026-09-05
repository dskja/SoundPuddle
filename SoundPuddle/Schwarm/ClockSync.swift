import Foundation

/// NTP-style offset estimation between local and host clocks.
final class ClockSync: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [(offsetMs: Double, rttMs: Double)] = []
    private(set) var offsetMs: Double = 0

    func record(t0: Int64, t1: Int64, t2: Int64, t3: Int64) {
        let t0d = Double(t0)
        let t1d = Double(t1)
        let t2d = Double(t2)
        let t3d = Double(t3)
        let offset = ((t1d - t0d) + (t2d - t3d)) / 2
        let rtt = (t3d - t0d) - (t2d - t1d)
        lock.lock()
        samples.append((offset, max(0, rtt)))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        // Prefer low-RTT samples
        let sorted = samples.sorted { $0.rttMs < $1.rttMs }
        let take = Array(sorted.prefix(max(1, sorted.count / 2)))
        offsetMs = take.map(\.offsetMs).reduce(0, +) / Double(take.count)
        lock.unlock()
    }

    func hostNowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000 + offsetMs)
    }

    func localMs(forHostMs host: Int64) -> Int64 {
        Int64(Double(host) - offsetMs)
    }

    func reset() {
        lock.lock()
        samples.removeAll()
        offsetMs = 0
        lock.unlock()
    }
}
