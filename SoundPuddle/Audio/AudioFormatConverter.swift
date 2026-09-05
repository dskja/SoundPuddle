import AVFoundation

final class AudioFormatConverter {
    private let target: AudioFormatSpec

    init(target: AudioFormatSpec = .canonical) {
        self.target = target
    }

    func convertToCanonicalPCM(_ buffer: AVAudioPCMBuffer) -> Data? { // shared by mic + file
        let outFormat = target.avFormat
        guard let converter = AVAudioConverter(from: buffer.format, to: outFormat) else {
            return int16Data(from: buffer)
        }

        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if error != nil { return nil }
        return int16Data(from: outBuffer)
    }

    private func int16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        if buffer.format.commonFormat == .pcmFormatInt16, let channels = buffer.int16ChannelData {
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            if buffer.format.isInterleaved {
                let byteCount = frameLength * channelCount * MemoryLayout<Int16>.size
                return Data(bytes: channels[0], count: byteCount)
            } else {
                var data = Data(capacity: frameLength * channelCount * 2)
                for frame in 0..<frameLength {
                    for ch in 0..<channelCount {
                        var sample = channels[ch][frame]
                        withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
                    }
                }
                return data
            }
        }

        guard let floatChannels = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let outChannels = Int(target.channels)
        var data = Data(capacity: frameLength * outChannels * 2)
        for frame in 0..<frameLength {
            if outChannels == 1 && channelCount > 1 {
                var sum: Float = 0
                for ch in 0..<channelCount { sum += floatChannels[ch][frame] }
                let clipped = max(-1.0, min(1.0, sum / Float(channelCount)))
                var sample = Int16(clipped * Float(Int16.max))
                withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
            } else {
                for ch in 0..<min(channelCount, outChannels) {
                    let clipped = max(-1.0, min(1.0, floatChannels[ch][frame]))
                    var sample = Int16(clipped * Float(Int16.max))
                    withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
                }
            }
        }
        return data
    }

    func makePCMBuffer(from pcm: Data, format: AudioFormatSpec = .canonical) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(pcm.count / (Int(format.channels) * (format.bitsPerSample / 8)))
        guard frameCount > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format.avFormat, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let dst = buffer.int16ChannelData?[0] else { return nil }
        pcm.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Int16.self).baseAddress else { return }
            dst.update(from: base, count: Int(frameCount) * Int(format.channels))
        }
        return buffer
    }
}
