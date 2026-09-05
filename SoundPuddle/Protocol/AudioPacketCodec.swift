import Foundation

enum AudioPacketCodec {
    static func encode(seq: UInt32, pcm: Data, format: AudioFormatSpec = .canonical) -> Data {
        let frameCount = UInt16(pcm.count / (Int(format.channels) * (format.bitsPerSample / 8)))
        let header = PacketHeader(
            version: UInt8(ProtocolVersion.major),
            flags: 0,
            seq: seq,
            sampleRate: UInt32(format.sampleRate),
            channels: UInt8(format.channels),
            bitsPerSample: UInt8(format.bitsPerSample),
            frameCount: frameCount
        )
        var packet = header.encode()
        packet.append(pcm)
        return packet
    }

    static func decode(_ data: Data, expected: AudioFormatSpec = .canonical) -> (header: PacketHeader, pcm: Data)? {
        guard let header = PacketHeader.decode(from: data) else { return nil }
        guard header.version == ProtocolVersion.major else { return nil }
        guard header.channels == UInt8(expected.channels) else { return nil }
        guard header.bitsPerSample == UInt8(expected.bitsPerSample) else { return nil }
        guard header.sampleRate == UInt32(expected.sampleRate) else { return nil }
        guard header.frameCount >= 80, header.frameCount <= 960 else { return nil }

        let payloadOffset = PacketHeader.size
        let expectedBytes = Int(header.frameCount) * Int(header.channels) * (Int(header.bitsPerSample) / 8)
        guard data.count >= payloadOffset + expectedBytes else { return nil }
        let pcm = data.subdata(in: payloadOffset..<(payloadOffset + expectedBytes))
        return (header, pcm)
    }
}
