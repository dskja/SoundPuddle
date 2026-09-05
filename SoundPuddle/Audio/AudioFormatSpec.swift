import Foundation
import AVFoundation

struct AudioFormatSpec: Equatable, Sendable {
    let sampleRate: Double
    let channels: AVAudioChannelCount
    let bitsPerSample: Int
    let frameDurationMs: Double

    static let canonical = AudioFormatSpec(
        sampleRate: 24_000,
        channels: 1,
        bitsPerSample: 16,
        frameDurationMs: 20
    )

    var token: String {
        "pcm16le-\(Int(sampleRate))-\(channels)"
    }

    var samplesPerFrame: AVAudioFrameCount {
        AVAudioFrameCount((sampleRate * frameDurationMs / 1000.0).rounded())
    }

    /// Alias used by capture/file timer paths.
    var samplesPerPacket: AVAudioFrameCount { samplesPerFrame }

    var bytesPerFrame: Int {
        Int(samplesPerFrame) * Int(channels) * (bitsPerSample / 8)
    }

    var avFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!
    }

    var floatFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
    }
}
