import AVFoundation
import Foundation

final class AudioCaptureEngine: NSObject {
    enum Source: Equatable {
        case microphone
        case file(URL)
    }

    private let engine = AVAudioEngine()
    private let previewPlayer = AVAudioPlayerNode()
    private let converter = AudioFormatConverter()
    private let assembler = FrameAssembler()
    private let sendQueue = DispatchQueue(label: "soundpuddle.audio.send")
    private var seq: UInt32 = 0
    private var file: AVAudioFile?
    private var displayLinkTimer: Timer?
    private var isRunning = false

    var onFrame: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?
    private(set) var source: Source = .microphone

    func start(source: Source) throws {
        stop()
        self.source = source
        assembler.reset()
        seq = 0

        engine.attach(previewPlayer)
        engine.connect(previewPlayer, to: engine.mainMixerNode, format: nil)

        switch source {
        case .microphone:
            try startMicrophone()
        case .file(let url):
            try startFile(url)
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        isRunning = false
        displayLinkTimer?.invalidate()
        displayLinkTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        previewPlayer.stop()
        if engine.isRunning { engine.stop() }
        file = nil
        assembler.reset()
    }

    private func startMicrophone() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleIncoming(buffer)
        }
    }

    private func startFile(_ url: URL) throws {
        let audioFile = try AVAudioFile(forReading: url)
        file = audioFile
        let format = audioFile.processingFormat
        previewPlayer.scheduleFile(audioFile, at: nil, completionHandler: nil)
        previewPlayer.play()

        // Read file in chunks on timer approximating realtime
        let frameSamples = Int(AudioFormatSpec.canonical.samplesPerFrame)
        displayLinkTimer = Timer.scheduledTimer(withTimeInterval: AudioFormatSpec.canonical.frameDurationMs / 1000.0, repeats: true) { [weak self] _ in
            guard let self, let file = self.file else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameSamples * 2)) else { return }
            do {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(min(frameSamples * 2, Int(file.length - file.framePosition))))
                if buffer.frameLength == 0 {
                    file.framePosition = 0
                    return
                }
                self.handleIncoming(buffer)
            } catch {
                // loop or stop silently
            }
        }
    }

    private func handleIncoming(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        updateLevel(buffer)
        guard let pcm = converter.convertToCanonicalPCM(buffer) else { return } // Int16 LE canonical
        let frames = assembler.push(pcm)
        sendQueue.async { [weak self] in
            guard let self else { return }
            for frame in frames {
                let packet = AudioPacketCodec.encode(seq: self.seq, pcm: frame)
                self.seq &+= 1
                self.onFrame?(packet)
            }
        }
    }

    private func updateLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData?[0] else {
            if let ints = buffer.int16ChannelData?[0] {
                var sum: Float = 0
                let n = Int(buffer.frameLength)
                for i in 0..<n {
                    let v = Float(ints[i]) / Float(Int16.max)
                    sum += v * v
                }
                let rms = sqrt(sum / Float(max(n, 1)))
                DispatchQueue.main.async { self.onLevel?(min(1, rms * 2.5)) }
            }
            return
        }
        var sum: Float = 0
        let n = Int(buffer.frameLength)
        for i in 0..<n {
            let v = channels[i]
            sum += v * v
        }
        let rms = sqrt(sum / Float(max(n, 1)))
        DispatchQueue.main.async { self.onLevel?(min(1, rms * 2.5)) }
    }
}
