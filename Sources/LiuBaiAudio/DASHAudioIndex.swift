import Foundation
import LiuBaiCore

public struct AudioByteRange: Sendable, Equatable {
    public let offset: Int64
    public let length: Int64
    public var end: Int64 { offset + length - 1 }
    public init(offset: Int64, length: Int64) { self.offset = offset; self.length = length }
}

/// Reads the existing ISO-BMFF sidx table. No audio decoding, transcoding, or
/// full-file scan is needed to expose the same AAC fragments as native HLS.
public struct DASHAudioIndex: Sendable {
    public struct Segment: Sendable {
        public let range: AudioByteRange
        public let duration: TimeInterval
    }
    public let initialization: Data
    public let segments: [Segment]
    public var duration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }

    public static func parse(_ data: Data) throws -> DASHAudioIndex? {
        func read(_ offset: Int, _ count: Int) throws -> UInt64 {
            guard offset >= 0, count > 0, offset <= data.count - count else { throw BilibiliError.invalidResponse }
            return data[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        var offset = 0
        var hasMovie = false
        while offset + 8 <= data.count {
            var size = try read(offset, 4)
            var header = 8
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if size == 1 { size = try read(offset + 8, 8); header = 16 }
            guard size >= UInt64(header), size <= UInt64(Int.max), size <= UInt64(data.count - offset) else { return nil }
            let end = offset + Int(size)
            if type == "moov" { hasMovie = true }
            if type == "sidx" {
                guard hasMovie else { throw BilibiliError.invalidResponse }
                let version = try read(offset + header, 1)
                guard version <= 1 else { throw BilibiliError.invalidResponse }
                let timescale = try read(offset + header + 8, 4)
                guard timescale > 0 else { throw BilibiliError.invalidResponse }
                let wide = version == 1
                let firstOffset = try read(offset + header + (wide ? 20 : 16), wide ? 8 : 4)
                var cursor = offset + header + (wide ? 30 : 22)
                let count = Int(try read(cursor, 2)); cursor += 2
                guard count > 0, cursor + count * 12 <= end, firstOffset <= UInt64(Int64.max) - UInt64(end) else { throw BilibiliError.invalidResponse }
                var byteOffset = Int64(end) + Int64(firstOffset)
                var segments: [Segment] = []
                for _ in 0..<count {
                    let reference = try read(cursor, 4)
                    let ticks = try read(cursor + 4, 4)
                    let length = Int64(reference & 0x7fff_ffff)
                    guard reference & 0x8000_0000 == 0, length > 0, length <= 8 * 1024 * 1024,
                          ticks > 0, byteOffset <= Int64.max - length else { throw BilibiliError.invalidResponse }
                    segments.append(Segment(range: AudioByteRange(offset: byteOffset, length: length), duration: Double(ticks) / Double(timescale)))
                    byteOffset += length
                    cursor += 12
                }
                return DASHAudioIndex(initialization: data.prefix(offset), segments: segments)
            }
            offset = end
        }
        return nil
    }

    public var playlist: Data {
        let target = Int(ceil(segments.map(\.duration).max() ?? 1))
        var lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-TARGETDURATION:\(max(1, target))", "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-INDEPENDENT-SEGMENTS", "#EXT-X-MAP:URI=\"init.mp4\""]
        for (index, segment) in segments.enumerated() {
            lines.append(String(format: "#EXTINF:%.6f,", locale: Locale(identifier: "en_US_POSIX"), segment.duration))
            lines.append("segment-\(index).m4s")
        }
        lines.append("#EXT-X-ENDLIST")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
