import AVFoundation
import Foundation

/// Near-ultrasonic chirp ranging (~18.5 kHz). True ultrasound is limited on iPhone speakers;
/// this band is audible only as a faint tick on most devices.
final class ChirpCalibrator: NSObject {
    enum Phase: Equatable {
        case idle
        case armed
        case playing
        case listening
        case done
        case failed(String)
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var phase: Phase = .idle
    private var detectionTimes: [Int64] = []
    private var onDetect: ((Int64) -> Void)?
    private var frequency: Double = 18_500

    var currentPhase: Phase {
        lock.lock(); defer { lock.unlock() }
        return phase
    }

    private func setPhase(_ p: Phase) {
        lock.lock(); phase = p; lock.unlock()
    }

    func prepare(frequencyHz: Double = 18_500) throws {
        stop()
        frequency = frequencyHz
        setPhase(.armed)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)

        engine.attach(player)
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.analyze(buffer)
        }
        try engine.start()
    }

    func playChirp(durationMs: Int = 80, atHostMs: Int64? = nil, clock: ClockSync? = nil) {
        setPhase(.playing)
        let sampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let frames = Int(sampleRate * Double(durationMs) / 1000.0)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.mainMixerNode.outputFormat(forBus: 0), frameCapacity: AVAudioFrameCount(frames)) else {
            setPhase(.failed("buffer"))
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        if let ch = buffer.floatChannelData?[0] {
            let f = frequency
            for i in 0..<frames {
                let t = Double(i) / sampleRate
                let env = min(1, Double(i) / 64) * min(1, Double(frames - i) / 64)
                ch[i] = Float(sin(2 * Double.pi * f * t) * env * 0.55)
            }
        }

        let play = { [weak self] in
            guard let self else { return }
            self.player.scheduleBuffer(buffer, completionHandler: nil)
            self.player.play()
            self.setPhase(.listening)
        }

        if let atHostMs, let clock {
            let local = clock.localFromHostMs(atHostMs)
            let delay = Double(local - ClockSync.nowMs()) / 1000.0
            if delay > 0.01 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: play)
                return
            }
        }
        play()
    }

    func armDetection(_ handler: @escaping (Int64) -> Void) {
        lock.lock()
        onDetect = handler
        detectionTimes.removeAll()
        phase = .listening
        lock.unlock()
    }

    /// Rough distance from host chirp ToA delta (speed of sound ~343 m/s), clamped.
    static func distanceMeters(deltaMs: Double) -> Double {
        let d = abs(deltaMs) / 1000.0 * 343.0
        return min(8, max(0.4, d))
    }

    func stop() {
        lock.lock()
        onDetect = nil
        phase = .idle
        detectionTimes.removeAll()
        lock.unlock()
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        if engine.isRunning { engine.stop() }
        engine.reset()
    }

    private func analyze(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let p = phase
        lock.unlock()
        guard p == .listening || p == .playing else { return }
        guard let ch = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        let sr = buffer.format.sampleRate
        let mag = goertzel(samples: ch, count: n, sampleRate: sr, targetHz: frequency)
        if mag > 0.08 {
            let t = ClockSync.nowMs()
            lock.lock()
            let should = detectionTimes.last.map({ t - $0 > 120 }) ?? true
            if should { detectionTimes.append(t) }
            let handler = onDetect
            lock.unlock()
            if should {
                DispatchQueue.main.async { handler?(t) }
            }
        }
    }

    private func goertzel(samples: UnsafePointer<Float>, count: Int, sampleRate: Double, targetHz: Double) -> Float {
        let k = Int(0.5 + (Double(count) * targetHz) / sampleRate)
        let w = (2.0 * Double.pi * Double(k)) / Double(count)
        let cosine = cos(w)
        let coeff = 2.0 * cosine
        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        for i in 0..<count {
            s0 = Double(samples[i]) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - coeff * s1 * s2
        return Float(sqrt(max(0, power)) / Double(count))
    }
}
