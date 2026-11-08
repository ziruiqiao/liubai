import Foundation
import LiuBaiAudio

enum AudioIndexChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw NSError(domain: "AudioIndex", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            count += 1
        }
        func integer(_ value: UInt64, _ length: Int) -> Data { Data((0..<length).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
        func box(_ type: String, _ body: Data) -> Data { integer(UInt64(body.count + 8), 4) + Data(type.utf8) + body }
        func fixture(wide: Bool = false, timescale: UInt64 = 1000, firstOffset: UInt64 = 0, reference: UInt64 = 100) -> Data {
            var header = integer(wide ? 1 : 0, 1) + Data(repeating: 0, count: 3)
            header += integer(1, 4) + integer(timescale, 4)
            header += integer(0, wide ? 8 : 4) + integer(firstOffset, wide ? 8 : 4)
            header += integer(0, 2) + integer(2, 2)
            header += integer(reference, 4) + integer(5000, 4) + integer(0x90000000, 4)
            header += integer(200, 4) + integer(6250, 4) + integer(0x90000000, 4)
            return box("ftyp", Data("dash0000".utf8)) + box("moov", Data()) + box("sidx", header)
        }
        let bytes = fixture()
        let index = try DASHAudioIndex.parse(bytes)!
        try check(index.initialization.count == 24 && index.segments.count == 2, "Index parsing must separate initialization from fragment references")
        try check(index.segments[0].range == AudioByteRange(offset: Int64(bytes.count), length: 100)
                  && index.segments[1].range.offset == Int64(bytes.count + 100), "Fragment byte ranges must follow sidx's end and cumulative lengths")
        try check(abs(index.duration - 11.25) < 0.00001, "Fragment durations must use the index's timescale")
        let playlist = String(decoding: index.playlist, as: UTF8.self)
        try check(playlist.contains("#EXT-X-TARGETDURATION:7") && playlist.contains("#EXTINF:6.250000,") && playlist.contains("#EXT-X-ENDLIST"),
                  "Native HLS must advertise VOD duration and a sufficiently long target duration")
        try check(!playlist.contains("http") && playlist.contains("#EXT-X-MAP:URI=\"init.mp4\""), "HLS must reference only local memory-served media")
        let wide = fixture(wide: true, firstOffset: 0x1_0000_0000)
        let wideIndex = try DASHAudioIndex.parse(wide)!
        try check(wideIndex.segments[0].range.offset == Int64(wide.count) + 0x1_0000_0000, "Version-1 sidx must retain 64-bit offsets")
        try check(try DASHAudioIndex.parse(box("ftyp", Data("M4A 0000".utf8))) == nil, "Ordinary MP4 must remain eligible for progressive fallback")
        try check(try DASHAudioIndex.parse(bytes.dropLast()) == nil, "A truncated index must never produce invented fragment ranges")
        for malformed in [fixture(timescale: 0), fixture(reference: 0x80000001), fixture(reference: 9 * 1024 * 1024), fixture(reference: 0)] {
            var refused = false
            do { _ = try DASHAudioIndex.parse(malformed) } catch { refused = true }
            try check(refused, "Invalid, hierarchical, empty, or oversized fragment references must be rejected before requesting data")
        }
        return count
    }
}
