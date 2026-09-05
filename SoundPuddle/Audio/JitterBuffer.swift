import Foundation

final class JitterBuffer: @unchecked Sendable {
    struct Metrics: Sendable {
        var lateDrops: Int = 0
        var gapsFilled: Int = 0
        var underruns: Int = 0
    }

    private let targetFrames: Int
    private let maxLateFrames: Int
    private var queue: [(seq: UInt32, pcm: Data)] = []
    private var expectedSeq: UInt32?
    private var started = false
    private(set) var metrics = Metrics()
    private let lock = NSLock()

    init(targetFrames: Int, maxLateFrames: Int = 8) {
        self.targetFrames = max(2, targetFrames)
        self.maxLateFrames = maxLateFrames
    }

    func reset(targetFrames: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let targetFrames {
            // target is immutable after init in current design; kept for API clarity
            _ = targetFrames
        }
        queue.removeAll(keepingCapacity: true)
        expectedSeq = nil
        started = false
        metrics = Metrics()
    }

    func push(seq: UInt32, pcm: Data) {
        lock.lock()
        defer { lock.unlock() }

        if let expected = expectedSeq {
            if seq &- expected > UInt32(maxLateFrames) && seq > expected {
                // skip to live
                expectedSeq = seq
                queue.removeAll(keepingCapacity: true)
            } else if seq < expected {
                metrics.lateDrops += 1
                return
            }
        } else {
            expectedSeq = seq
        }

        if let idx = queue.firstIndex(where: { $0.seq >= seq }) {
            if queue[idx].seq == seq { return }
            queue.insert((seq, pcm), at: idx)
        } else {
            queue.append((seq, pcm))
        }
    }

    func pop() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard let expected = expectedSeq else { return nil }
        if !started {
            guard queue.count >= targetFrames else { return nil }
            started = true
        }

        if let first = queue.first, first.seq == expected {
            queue.removeFirst()
            expectedSeq = expected &+ 1
            return first.pcm
        }

        if let first = queue.first, first.seq > expected {
            // gap — return silence-sized nil signal via empty Data marker? use silence outside
            metrics.gapsFilled += 1
            expectedSeq = expected &+ 1
            return Data() // caller treats empty as silence frame request
        }

        metrics.underruns += 1
        return nil
    }

    var hasStarted: Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }

    var bufferedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return queue.count
    }
}
