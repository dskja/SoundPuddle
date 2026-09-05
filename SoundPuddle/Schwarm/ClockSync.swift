import Foundation

/// Lightweight NTP-style offset vs host clock (hostTime ≈ local + offsetMs).
final class ClockSync: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [(rtt: Int64, offset: Int64)] = []
    private var offsetMs: Int64 = 0
    private var rttMs: Int64 = 0

    var currentOffsetMs: Int64 {
        lock.lock(); defer { lock.unlock() }
        return offsetMs
    }

    var lastRTTMs: Int64 {
        lock.lock(); defer { lock.unlock() }
        return rttMs
    }

    /// Join sends `t0` (local). Host replies with `t0`, `t1` (host recv), `t2` (host send).
    /// Join finishes with `t3` (local recv): offset = ((t1 - t0) + (t2 - t3)) / 2
    func recordSample(t0: Int64, t1: Int64, t2: Int64, t3: Int64) {
        let rtt = max(0, (t3 - t0) - (t2 - t1))
        let offset = ((t1 - t0) + (t2 - t3)) / 2
        lock.lock()
        samples.append((rtt, offset))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        let sorted = samples.sorted { $0.rtt < $1.rtt }
        let take = max(1, sorted.count / 2)
        let best = Array(sorted.prefix(take))
        offsetMs = best.map(\.offset).reduce(0, +) / Int64(best.count)
        rttMs = best.map(\.rtt).reduce(0, +) / Int64(best.count)
        lock.unlock()
    }

    func hostNowMs() -> Int64 {
        nowMs() + currentOffsetMs
    }

    func localFromHostMs(_ hostMs: Int64) -> Int64 {
        hostMs - currentOffsetMs
    }

    static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    func nowMs() -> Int64 { Self.nowMs() }

    func reset() {
        lock.lock()
        samples.removeAll()
        offsetMs = 0
        rttMs = 0
        lock.unlock()
    }
}
