import AVFoundation
import Foundation

final class AudioPlaybackEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let converter = AudioFormatConverter()
    private let playQueue = DispatchQueue(label: "soundpuddle.audio.play")
    private var jitter: JitterBuffer
    private var pumpTimer: Timer?
    private var isRunning = false
    private let format = AudioFormatSpec.canonical

    var onLevel: ((Float) -> Void)?
    var onUnderrun: (() -> Void)?
    var outputVolume: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = max(0, min(1, outputVolume)) }
    }
    /// Join-side spatial pan for mono streams.
    var speakerRole: SpeakerRole = .mid

    init(targetFrames: Int = 3) {
        jitter = JitterBuffer(targetFrames: targetFrames)
    }

    func prepare(targetFrames: Int) throws {
        stop()
        jitter = JitterBuffer(targetFrames: targetFrames)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format.avFormat)
        try engine.start()
        engine.mainMixerNode.outputVolume = max(0, min(1, outputVolume))
        player.play()
        isRunning = true
        startPump()
    }

    func stop() {
        isRunning = false
        pumpTimer?.invalidate()
        pumpTimer = nil
        player.stop()
        if engine.isRunning { engine.stop() }
        engine.reset()
        jitter.reset()
    }

    func enqueue(packet: Data) {
        guard let decoded = AudioPacketCodec.decode(packet) else { return }
        let pcm = speakerRole == .mid ? decoded.pcm : SpatialRouter.applyPan(decoded.pcm, role: speakerRole)
        jitter.push(seq: decoded.header.seq, pcm: pcm)
    }

    private func startPump() {
        let timer = Timer(timeInterval: format.frameDurationMs / 1000.0, repeats: true) { [weak self] _ in
            self?.pump()
        }
        RunLoop.main.add(timer, forMode: .common)
        pumpTimer = timer
    }

    private func pump() {
        playQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            guard let pcm = self.jitter.pop() else {
                if self.jitter.hasStarted {
                    DispatchQueue.main.async { self.onUnderrun?() }
                }
                return
            }
            let data = pcm.isEmpty ? Data(count: self.format.bytesPerFrame) : pcm
            guard let buffer = self.converter.makePCMBuffer(from: data, format: self.format) else { return }
            self.player.scheduleBuffer(buffer, completionHandler: nil)
            self.emitLevel(from: data)
        }
    }

    private func emitLevel(from pcm: Data) {
        let samples = pcm.count / 2
        guard samples > 0 else { return }
        var sum: Float = 0
        pcm.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<samples {
                let v = Float(ptr[i]) / Float(Int16.max)
                sum += v * v
            }
        }
        let rms = sqrt(sum / Float(samples))
        DispatchQueue.main.async { self.onLevel?(min(1, rms * 2.5)) }
    }
}
