import AVFoundation
import Foundation

/// Builds L / R / mid stems from a stereo (or mono) buffer and mixes for a role.
enum SpatialRouter {
    struct Stems {
        var left: Data
        var right: Data
        var mid: Data
    }

    static func stems(from buffer: AVAudioPCMBuffer, bytesPerFrame: Int) -> Stems? {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }

        var left = [Int16](repeating: 0, count: frames)
        var right = [Int16](repeating: 0, count: frames)
        var mid = [Int16](repeating: 0, count: frames)

        if let ch = buffer.floatChannelData {
            let channels = Int(buffer.format.channelCount)
            for i in 0..<frames {
                let l = ch[0][i]
                let r = channels > 1 ? ch[1][i] : l
                left[i] = clamp16(l)
                right[i] = clamp16(r)
                mid[i] = clamp16((l + r) * 0.5)
            }
        } else if let ints = buffer.int16ChannelData {
            let channels = Int(buffer.format.channelCount)
            for i in 0..<frames {
                let l = Float(ints[0][i]) / Float(Int16.max)
                let r: Float
                if channels > 1 {
                    r = Float(ints[1][i]) / Float(Int16.max)
                } else {
                    r = l
                }
                left[i] = clamp16(l)
                right[i] = clamp16(r)
                mid[i] = clamp16((l + r) * 0.5)
            }
        } else {
            return nil
        }

        return Stems(
            left: int16Data(left),
            right: int16Data(right),
            mid: int16Data(mid)
        )
    }

    static func mix(stems: Stems, role: SpeakerRole, targetBytes: Int) -> Data {
        let g = role.stemGains
        let n = min(stems.left.count, stems.right.count, stems.mid.count) / 2
        var out = [Int16](repeating: 0, count: n)
        stems.left.withUnsafeBytes { lb in
            stems.right.withUnsafeBytes { rb in
                stems.mid.withUnsafeBytes { mb in
                    let l = lb.bindMemory(to: Int16.self)
                    let r = rb.bindMemory(to: Int16.self)
                    let m = mb.bindMemory(to: Int16.self)
                    for i in 0..<n {
                        let v = Float(l[i]) * g.l + Float(r[i]) * g.r + Float(m[i]) * g.mid
                        out[i] = clamp16(v / Float(Int16.max) / max(0.01, g.l + g.r + g.mid) * 1.4)
                    }
                }
            }
        }
        var data = int16Data(out)
        if data.count < targetBytes {
            data.append(Data(count: targetBytes - data.count))
        } else if data.count > targetBytes {
            data = data.prefix(targetBytes)
        }
        return data
    }

    /// Join-side pan envelope for mono streams (fallback when host sends one mix).
    static func applyPan(_ pcm: Data, role: SpeakerRole) -> Data {
        let pan = role.pan
        let gain = 0.65 + (1 - abs(pan)) * 0.35
        var samples = [Int16](repeating: 0, count: pcm.count / 2)
        pcm.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<samples.count {
                samples[i] = clamp16(Float(src[i]) / Float(Int16.max) * gain)
            }
        }
        return int16Data(samples)
    }

    private static func clamp16(_ v: Float) -> Int16 {
        let c = max(-1, min(1, v))
        return Int16((c * Float(Int16.max)).rounded())
    }

    private static func int16Data(_ samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
