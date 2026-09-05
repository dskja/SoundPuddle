import Foundation

final class FrameAssembler: @unchecked Sendable {
    private let bytesPerFrame: Int
    private var pending = Data()
    private let lock = NSLock()

    init(format: AudioFormatSpec = .canonical) {
        self.bytesPerFrame = format.bytesPerFrame
    }

    func push(_ data: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var frames: [Data] = []
        while pending.count >= bytesPerFrame {
            let frame = pending.prefix(bytesPerFrame)
            frames.append(Data(frame))
            pending.removeFirst(bytesPerFrame)
        }
        return frames
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        pending.removeAll(keepingCapacity: true)
    }
}
