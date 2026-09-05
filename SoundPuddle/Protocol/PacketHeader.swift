import Foundation

struct PacketHeader: Equatable, Sendable {
    static let magic: UInt32 = 0x5350_5544 // SPUD
    static let size = 18

    var version: UInt8
    var flags: UInt8
    var seq: UInt32
    var sampleRate: UInt32
    var channels: UInt8
    var bitsPerSample: UInt8
    var frameCount: UInt16

    func encode() -> Data {
        var data = Data(capacity: Self.size)
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        appendLE(Self.magic)
        data.append(version)
        data.append(flags)
        appendLE(seq)
        appendLE(sampleRate)
        data.append(channels)
        data.append(bitsPerSample)
        appendLE(frameCount)
        return data
    }

    static func decode(from data: Data) -> PacketHeader? {
        guard data.count >= size else { return nil }
        func readU32(_ offset: Int) -> UInt32 {
            data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        }
        func readU16(_ offset: Int) -> UInt16 {
            data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        }
        let magic = readU32(0)
        guard magic == Self.magic else { return nil }
        return PacketHeader(
            version: data[4],
            flags: data[5],
            seq: readU32(6),
            sampleRate: readU32(10),
            channels: data[14],
            bitsPerSample: data[15],
            frameCount: readU16(16)
        )
    }
}
