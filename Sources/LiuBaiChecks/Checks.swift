import AVFoundation
import Foundation
import LiuBaiAudio
import LiuBaiCore

private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
struct Checks {
    private static var passed = 0
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
        passed += 1
    }

    @MainActor
    static func main() async {
        do {
            try timerChecks()
            passed += try PomodoroJournalChecks.run()
            try statisticsChecks()
            passed += try FocusHistoryChecks.run()
            try persistenceChecks()
            try referenceChecks()
            passed += try await LibraryChecks.run()
            passed += try MusicMembershipChecks.run()
            passed += try AudioIndexChecks.run()
            passed += try SkyChecks.run()
            passed += try await WeatherChecks.run()
            print("PASS: \(passed) core checks")
            if CommandLine.arguments.contains("--weather-network") {
                // A public test city, never the user's system location.
                let coordinate = try WeatherCoordinate(latitude: 39.9, longitude: 116.4)
                let value = try await WeatherClient().current(at: coordinate)
                try expect(value.isFresh(at: Date()), "The live provider must return current model data")
                print("PASS: live weather API, code=\(value.code), temperature=\(value.temperature) C, no device location requested")
            }
            if let index = CommandLine.arguments.firstIndex(of: "--repair-library"), CommandLine.arguments.indices.contains(index + 1) {
                try repairLibrary(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            }
            if CommandLine.arguments.contains("--diagnose") { await diagnoseHTTP() }
            if let index = CommandLine.arguments.firstIndex(of: "--network") {
                let reference = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "BV17x411w7KC"
                try await networkCheck(reference: reference)
            }
            if let index = CommandLine.arguments.firstIndex(of: "--collection"), CommandLine.arguments.indices.contains(index + 1) {
                let result = try await BilibiliClient().collection(CommandLine.arguments[index + 1])
                try expect(result.tracks.count > 30, "The supplied collection must load all pages, not only its first page")
                try expect(result.tracks.allSatisfy { $0.cid == 0 }, "Season import must store metadata without resolving or downloading audio")
                print("PASS: collection loaded across all pages (\(result.tracks.count) metadata entries)")
                var data = AppData()
                data.tracks = result.tracks
                data.collections = [LibraryCollection(id: result.id, title: result.title, kind: result.kind, sourceURL: result.sourceURL, trackKeys: result.tracks.map(\.libraryKey))]
                print("Collection storage: \(try FileStore.encode(data).count / 1024) KiB of JSON metadata, zero audio files")
                if CommandLine.arguments.contains("--play-first"), let first = result.tracks.first { try await playCheck(track: first, client: BilibiliClient()) }
            }
            if CommandLine.arguments.contains("--qr") {
                let client = FavoritesClient()
                let challenge = try await client.beginLogin()
                if case .waiting = try await client.poll(challenge) { print("PASS: live QR generation and pending status (no account login performed)") }
                else { throw CheckFailure(message: "A new QR must be waiting for a scan") }
            }
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func timerChecks() throws {
        var preferences = Preferences()
        preferences.focusMinutes = 1
        preferences.roundsBeforeLongBreak = 2
        let start = Date(timeIntervalSince1970: 1_000_000)
        var timer = PomodoroEngine()
        timer.reset(preferences: preferences)
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(23))
        try expect(timer.remaining == 37 && !timer.isRunning, "Pause must retain the exact remaining duration")
        timer.start(at: start.addingTimeInterval(100))
        try expect(timer.advance(to: start.addingTimeInterval(136), preferences: preferences) == nil, "A paused interval must not count toward completion")
        let first = timer.advance(to: start.addingTimeInterval(140), preferences: preferences)
        try expect(first?.finishedAt == start.addingTimeInterval(137), "Completion must use the deadline, not a late tick")
        try expect(timer.phase == .shortBreak && timer.completedInCycle == 1, "The first completed round must lead to a short break")
        try expect(timer.advance(to: start.addingTimeInterval(500), preferences: preferences) == nil, "A completion must be emitted exactly once")
        timer.select(.focus, preferences: preferences)
        timer.start(at: start)
        _ = timer.advance(to: start.addingTimeInterval(61), preferences: preferences)
        try expect(timer.phase == .longBreak && timer.completedInCycle == 0, "The configured cycle must end with a long break")
        timer.select(.focus, preferences: preferences)
        timer.start(at: start)
        timer.reset(preferences: preferences)
        try expect(timer.completedInCycle == 0, "Resetting a partial round must not count as a completed round")
        preferences.autoStartBreak = true
        timer.start(at: start)
        _ = timer.advance(to: start.addingTimeInterval(6000), preferences: preferences)
        try expect(timer.phase == .shortBreak && timer.secondsRemaining(at: start.addingTimeInterval(6000)) == 300,
                   "A suspended process must not invent rounds or consume the next break")
        let snapshot = timer.pausedSnapshot(at: start.addingTimeInterval(6010))
        try expect(!snapshot.isRunning && snapshot.remaining == 290, "Restored timers must be paused")
    }

    private static func repairLibrary(directory: URL) throws {
        let store = FileStore(directory: directory)
        let originalBytes = try Data(contentsOf: store.fileURL)
        let original = try FileStore.decode(originalBytes)
        let backup = directory.appendingPathComponent("liubai-before-0.4.0-\(Int(Date().timeIntervalSince1970)).json")
        try originalBytes.write(to: backup, options: .withoutOverwriting)
        var repaired = try store.load()
        repaired.removeImportedFavorites()
        try expect(repaired.journal == original.journal && repaired.dailyStats == original.dailyStats
                   && repaired.preferences == original.preferences && repaired.timer == original.timer
                   && repaired.intention == original.intention, "Library repair must preserve all non-music data")
        try store.save(repaired)
        print("Library repaired: \(original.tracks.count) → \(repaired.tracks.count) metadata records; My Music=\(repaired.myMusic.count); collections=\(repaired.collections?.count ?? 0); imported favorites=\(repaired.collections?.filter { $0.kind == .favorites }.count ?? 0)")
        print("Original backup: \(backup.path)")
    }

    private static func statisticsChecks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 59, second: 30))!
        var days: [String: DailyStats] = [:]
        Statistics.record(from: start, to: start.addingTimeInterval(90), usage: true, listening: true, focus: true, into: &days, calendar: calendar)
        try expect(days["2026-11-08"]?.usageSeconds == 30, "Usage must split at local midnight")
        try expect(days["2026-11-09"]?.focusSeconds == 60, "Focus must carry into the next local day")
        try expect(days["2026-11-09"]?.usageSeconds == 60, "Simultaneous music and focus must not double total usage")
        Statistics.completeRound(at: start.addingTimeInterval(15), into: &days, calendar: calendar)
        try expect(days["2026-11-08"]?.completedRounds == 1 && days["2026-11-09"]?.completedRounds == 0,
                   "Completed rounds must belong to the completion day")
        Statistics.record(from: start, to: start.addingTimeInterval(-1), usage: true, listening: false, focus: false, into: &days, calendar: calendar)
        try expect(days["2026-11-08"]?.usageSeconds == 30, "Backward clock jumps must not subtract usage")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let dstEnd = calendar.date(byAdding: .day, value: 1, to: dstStart)!
        var dstDays: [String: DailyStats] = [:]
        Statistics.record(from: dstStart, to: dstEnd, usage: true, listening: false, focus: false, into: &dstDays, calendar: calendar)
        try expect(dstDays["2026-03-08"]?.usageSeconds == 23 * 3600 && dstDays.count == 1, "Day boundaries must respect daylight-saving time")
    }

    private static func persistenceChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liubai-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileStore(directory: directory)
        var data = try store.load()
        try expect(data.tracks.isEmpty, "A fresh installation must not contain fabricated tracks or statistics")
        var entry = JournalEntry(id: "2026-11-08")
        entry.body = "今天留一点空白。\n第二行。"
        data.journal[entry.id] = entry
        data.preferences.focusMinutes = 45
        try store.save(data)
        let restored = try store.load()
        try expect(restored.journal[entry.id]?.body == entry.body && restored.preferences.focusMinutes == 45, "Journal and settings must survive a full disk round trip")
        data.intention = "写作"
        try store.save(data)
        let backup = try FileStore.decode(Data(contentsOf: store.backupURL))
        try expect(backup.intention.isEmpty, "An earlier valid snapshot must remain available as a backup")
        let corrupt = Data("{invalid".utf8)
        try corrupt.write(to: store.fileURL)
        var rejected = false
        do { try store.save(data) } catch { rejected = true }
        let untouched = try Data(contentsOf: store.fileURL)
        try expect(rejected && untouched == corrupt, "Corrupted data must not be silently overwritten")
    }

    private static func referenceChecks() throws {
        let bv = try VideoReference.parse("https://www.bilibili.com/video/BV1GJ411x7h7/?p=2&share_source=copy_web")
        try expect(bv.bvid == "BV1GJ411x7h7" && bv.page == 2, "Video links must retain the selected part")
        let share = try VideoReference.parse("推荐给你：BV1GJ411x7h7，一起听歌")
        try expect(share.bvid == "BV1GJ411x7h7", "Shared text must accept an embedded BV identifier")
        let sharedPart = try VideoReference.parse("【一起听歌】 https://www.bilibili.com/video/BV17x411w7KC/?p=2，来自分享")
        try expect(sharedPart.page == 2, "A URL embedded in share text must retain its selected part")
        let av = try VideoReference.parse("av170001")
        try expect(av.aid == "170001", "Legacy av identifiers must be accepted")
        let key = try WBISigner.mixinKey(imageKey: "7cd084941338484aae1ad9425b84077c", subKey: "4932caff0ff746eab6f01bf08b70ac45")
        try expect(key == "ea1db124af3c7062474693fa704f4ff8", "WBI key permutation must match the protocol fixture")
        let query = WBISigner.query(["foo": "a !'()*中"], mixinKey: key, timestamp: 1702204169)
        try expect(query.hasPrefix("foo=a%20%E4%B8%AD&wts=1702204169&w_rid="), "WBI signing must remove forbidden characters and percent-encode UTF-8")
    }

    @MainActor
    private static func networkCheck(reference: String) async throws {
        let client = BilibiliClient()
        let started = Date()
        let track = try await client.resolve(reference)
        print(String(format: "PASS: public video metadata resolved (%.2f s, %.0f-minute audio)", Date().timeIntervalSince(started), track.duration / 60))
        try await playCheck(track: track, client: client)
    }

    @MainActor
    private static func playCheck(track: Track, client: BilibiliClient) async throws {
        let started = Date()
        let stream = try await client.audio(for: track)
        print(String(format: "PASS: signed DASH audio resolved (%.2f s, %d bit/s)", Date().timeIntervalSince(started), stream.bandwidth))
        print("Audio CDN candidates: \(stream.urls.compactMap(\.host).joined(separator: ", "))")
        if CommandLine.arguments.contains("--inspect-stream") { try await inspectStream(stream.urls[0]); return }
        let legacy = CommandLine.arguments.contains("--legacy-buffering")
        let resource = legacy ? AudioResource(url: stream.urls[0]) : try await AudioResource.streaming(url: stream.urls[0])
        defer { resource.cancel() }
        let playback = StreamingPlayback()
        let item = playback.replace(with: resource.asset)
        let player = playback.player
        if legacy { player.automaticallyWaitsToMinimizeStalling = true; item.preferredForwardBufferDuration = 15 }
        player.volume = 0
        let playbackStarted = Date()
        playback.play()
        let limit = Date().addingTimeInterval(20)
        var readyLogged = false
        while player.currentTime().seconds < 0.3 && Date() < limit {
            if !readyLogged && item.status == .readyToPlay {
                readyLogged = true
                print(String(format: "Ready: %.2f s, received %.0f KiB", Date().timeIntervalSince(playbackStarted), Double(resource.transferredBytes) / 1024))
            }
            if item.status == .failed { throw item.error ?? BilibiliError.noAudio }
            try await Task.sleep(for: .milliseconds(200))
        }
        let played = player.currentTime().seconds
        if played < 0.3 { print("Playback diagnostic: status=\(item.status.rawValue) rate=\(player.rate) waiting=\(player.reasonForWaitingToPlay?.rawValue ?? "none") buffered=\(item.loadedTimeRanges.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds })") }
        try expect(played >= 0.3, "AVPlayer must actually advance using the streamed audio")
        print(String(format: "First playback: %.2f s; received %.0f KiB; mode=%@", Date().timeIntervalSince(playbackStarted), Double(resource.transferredBytes) / 1024, legacy ? "previous" : "streaming"))
        if resource.usesIndexedSegments { try expect(resource.transferredBytes < 2 * 1024 * 1024, "Indexed audio must start before downloading megabytes of the song") }
        let playable = try await resource.asset.load(.isPlayable)
        let audioTracks = try await resource.asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await resource.asset.loadTracks(withMediaType: .video)
        let itemTypes = item.tracks.compactMap { $0.assetTrack?.mediaType }
        try expect(playable && (!audioTracks.isEmpty || itemTypes.contains(.audio)) && videoTracks.isEmpty && !itemTypes.contains(.video), "The loaded media must contain audio and zero video tracks")
        let chime = CompletionChime()
        try expect(chime.play(volume: 0), "The completion chime must use an independent playable audio stream")
        let beforeChime = player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(750))
        try expect(player.currentItem === item && player.rate > 0 && player.currentTime().seconds > beforeChime + 0.2,
                   "A completion chime must not pause or replace the music stream")
        playback.pause()
        let target = item.duration.seconds.isFinite ? item.duration.seconds * 0.75 : 30
        let beforeSeek = resource.transferredBytes
        let seeked = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        try expect(seeked && abs(player.currentTime().seconds - target) < 1, "Audio byte ranges must support seeking far into a long recording")
        if resource.usesIndexedSegments { try expect(resource.transferredBytes - beforeSeek < 2 * 1024 * 1024, "Seeking must fetch the target fragments rather than all preceding audio") }
        print("PASS: native audio playback, seeking, zero video tracks, and uninterrupted playback during the chime")
    }

    private static func inspectStream(_ url: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue(BilibiliClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BilibiliClient.referer, forHTTPHeaderField: "Referer")
        request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        let (data, _) = try await session.data(for: request)
        func uint(_ offset: Int, _ length: Int) -> UInt64 {
            guard offset >= 0 && offset + length <= data.count else { return 0 }
            return data[offset..<(offset + length)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        func boxes(_ start: Int, _ end: Int, _ indent: String = "") {
            var offset = start
            while offset + 8 <= end {
                let size = Int(uint(offset, 4))
                let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
                print("\(indent)\(type) @\(offset) size=\(size)")
                guard size >= 8, offset + size <= end else { break }
                if ["moov", "trak", "mdia", "minf", "stbl", "mvex"].contains(type) { boxes(offset + 8, offset + size, indent + "  ") }
                if ["mvhd", "mdhd"].contains(type) { print("\(indent)  v=\(uint(offset + 8, 1)) timescale=\(uint(offset + 20, 4)) duration=\(uint(offset + 24, 4))") }
                offset += size
            }
        }
        boxes(0, data.count)
    }

    private static func diagnoseHTTP() async {
        for agent in ["", BilibiliClient.userAgent, "curl/8.7.1"] {
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 15
                var headers = ["Referer": BilibiliClient.referer]
                if !agent.isEmpty { headers["User-Agent"] = agent }
                configuration.httpAdditionalHeaders = headers
                let session = URLSession(configuration: configuration)
                let (data, response) = try await session.data(from: URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=BV1GJ411x7h7")!)
                let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("HTTP diagnostic: UA=\(agent.isEmpty ? "system" : String(agent.prefix(20))) status=\((response as? HTTPURLResponse)?.statusCode ?? 0) code=\(String(describing: body?["code"])) message=\(String(describing: body?["message"]))")
                session.invalidateAndCancel()
            } catch { print("HTTP diagnostic: \(error.localizedDescription)") }
        }
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = [:]
            configuration.httpAdditionalHeaders = ["User-Agent": BilibiliClient.userAgent, "Referer": BilibiliClient.referer]
            let session = URLSession(configuration: configuration)
            for path in ["/x/web-interface/nav", "/x/web-interface/view?bvid=BV17x411w7KC", "/x/web-interface/view?aid=170001"] {
                let (data, response) = try await session.data(from: URL(string: "https://api.bilibili.com" + path)!)
                let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("HTTP direct: \(path) status=\((response as? HTTPURLResponse)?.statusCode ?? 0) code=\(String(describing: body?["code"])) message=\(String(describing: body?["message"]))")
            }
            session.invalidateAndCancel()
        } catch { print("HTTP direct: \(error.localizedDescription)") }
    }
}
