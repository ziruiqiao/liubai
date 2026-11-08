import Foundation

extension BilibiliClient {
    public func collection(_ input: String, progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> LibraryPreview {
        let expanded = try await expandShortLink(input)
        switch try CollectionReference.parse(expanded) {
        case .season(let id, let owner): return try await season(id: id, ownerID: owner, progress: progress)
        case .series(let id, let owner): return try await series(id: id, ownerID: owner, progress: progress)
        case .video(let reference):
            var params: [String: String] = [:]
            if let bvid = reference.bvid { params["bvid"] = bvid }
            if let aid = reference.aid { params["aid"] = aid }
            let envelope: Envelope<VideoData> = try await request("/x/web-interface/view", parameters: params)
            try check(envelope.code, message: envelope.message)
            guard let video = envelope.data else { throw BilibiliError.invalidResponse }
            if video.pages.count > 1 {
                let tracks = video.pages.map { Track(bvid: video.bvid, cid: $0.cid, title: "\(video.title) · P\($0.page) \($0.part)", artist: video.owner.name, duration: Double($0.duration), page: $0.page) }
                await progress(tracks.count, tracks.count)
                return LibraryPreview(id: "parts:\(video.bvid)", title: video.title, kind: .parts, sourceURL: "https://www.bilibili.com/video/\(video.bvid)/", tracks: tracks)
            }
            if let season = video.ugc_season { return try await self.season(id: season.id, ownerID: season.mid ?? video.owner.mid, progress: progress) }
            throw BilibiliError.unavailable("这个视频只有一个分 P，也没有关联的 UP 主合集。可以通过“添加音乐”单独加入。")
        }
    }

    private func season(id: Int64, ownerID: Int64?, progress: @Sendable (Int, Int) async -> Void) async throws -> LibraryPreview {
        var result = LibraryPageAccumulator()
        var page = 1
        let size = 30
        var name = "UP 主合集"
        var owner = ownerID
        while true {
            try Task.checkCancellation()
            let tracks: [Track]
            let total: Int
            if let ownerID = owner {
                let envelope: Envelope<SeasonArchivesData> = try await request("/x/polymer/web-space/seasons_archives_list", parameters: ["mid": String(ownerID), "season_id": String(id), "page_num": String(page), "page_size": String(size), "sort_reverse": "false"])
                try check(envelope.code, message: envelope.message)
                guard let data = envelope.data else { throw BilibiliError.invalidResponse }
                name = data.meta.title ?? data.meta.name ?? name
                total = data.page?.total ?? data.meta.total ?? data.archives.count
                tracks = data.archives.compactMap { $0.track(artist: "UP 主合集") }
            } else {
                let key = try await signingKey()
                let query = WBISigner.query(["season_id": String(id), "pn": String(page), "ps": String(size)], mixinKey: key, timestamp: Int(Date().timeIntervalSince1970))
                let envelope: Envelope<SeasonMediaData> = try await request("/x/space/fav/season/list", encodedQuery: query)
                try check(envelope.code, message: envelope.message)
                guard let data = envelope.data else { throw BilibiliError.invalidResponse }
                owner = data.info.upper?.mid
                // Keep this pagination route for this request; switching APIs at
                // a later page could change ordering and omit entries.
                return try await seasonMedia(id: id, first: data, progress: progress)
            }
            let hasMore = page * size < total
            try result.append(tracks, hasMore: hasMore)
            await progress(result.tracks.count, total)
            if !hasMore {
                let url = "https://space.bilibili.com/\(owner ?? 0)/lists/\(id)?type=season"
                return LibraryPreview(id: "season:\(id)", title: name, kind: .season, sourceURL: url, tracks: result.tracks, skippedCount: max(0, total - result.tracks.count))
            }
            page += 1
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func seasonMedia(id: Int64, first: SeasonMediaData, progress: @Sendable (Int, Int) async -> Void) async throws -> LibraryPreview {
        var result = LibraryPageAccumulator()
        var page = 1
        var data = first
        while true {
            try Task.checkCancellation()
            let total = data.info.media_count
            let hasMore = page * 30 < total
            try result.append((data.medias ?? []).compactMap { $0.track(artist: $0.upper?.name ?? data.info.upper?.name ?? "UP 主合集") }, hasMore: hasMore)
            await progress(result.tracks.count, total)
            if !hasMore {
                return LibraryPreview(id: "season:\(id)", title: data.info.title, kind: .season,
                                      sourceURL: "https://space.bilibili.com/\(data.info.upper?.mid ?? 0)/lists/\(id)?type=season", tracks: result.tracks, skippedCount: max(0, total - result.tracks.count))
            }
            page += 1
            try await Task.sleep(for: .milliseconds(150))
            let key = try await signingKey()
            let query = WBISigner.query(["season_id": String(id), "pn": String(page), "ps": "30"], mixinKey: key, timestamp: Int(Date().timeIntervalSince1970))
            let envelope: Envelope<SeasonMediaData> = try await request("/x/space/fav/season/list", encodedQuery: query)
            try check(envelope.code, message: envelope.message)
            guard let next = envelope.data else { throw BilibiliError.invalidResponse }
            data = next
        }
    }

    private func series(id: Int64, ownerID: Int64?, progress: @Sendable (Int, Int) async -> Void) async throws -> LibraryPreview {
        let envelope: Envelope<SeriesInfoData> = try await request("/x/series/series", parameters: ["series_id": String(id)])
        try check(envelope.code, message: envelope.message)
        guard let meta = envelope.data?.meta else { throw BilibiliError.invalidResponse }
        let owner = ownerID ?? meta.mid
        var result = LibraryPageAccumulator()
        var page = 1
        while true {
            try Task.checkCancellation()
            let envelope: Envelope<SeriesArchivesData> = try await request("/x/series/archives", parameters: ["mid": String(owner), "series_id": String(id), "pn": String(page), "ps": "30", "sort": "asc", "only_normal": "true"])
            try check(envelope.code, message: envelope.message)
            guard let data = envelope.data else { throw BilibiliError.invalidResponse }
            let hasMore = page * 30 < data.page.total
            try result.append(data.archives.compactMap { $0.track(artist: "UP 主系列") }, hasMore: hasMore)
            await progress(result.tracks.count, data.page.total)
            if !hasMore {
                return LibraryPreview(id: "series:\(id)", title: meta.name, kind: .series, sourceURL: "https://space.bilibili.com/\(owner)/lists/\(id)?type=series", tracks: result.tracks, skippedCount: max(0, data.page.total - result.tracks.count))
            }
            page += 1
            try await Task.sleep(for: .milliseconds(150))
        }
    }
}

struct LibraryArchive: Decodable {
    let id: Int64?
    let aid: Int64?
    let bvid: String?
    let bv_id: String?
    let title: String
    let duration: Int?
    let upper: Upper?
    let attr: Int?
    let type: Int?
    var rawKey: String {
        if let id = id ?? aid { return "\(type ?? 2):\(id)" }
        return bvid ?? bv_id ?? title
    }
    struct Upper: Decodable { let name: String?; let mid: Int64? }
    func track(artist: String) -> Track? {
        guard let bvid = [bvid, bv_id].compactMap({ $0 }).first(where: { $0.hasPrefix("BV") && $0.count == 12 }),
              (attr ?? 0) & 1 == 0, type == nil || type == 2 else { return nil }
        return Track(bvid: bvid, cid: 0, title: title, artist: upper?.name ?? artist, duration: Double(duration ?? 0), page: 1)
    }
}
private struct SeasonArchivesData: Decodable {
    let archives: [LibraryArchive]
    let meta: Meta
    let page: Page?
    struct Meta: Decodable { let name: String?; let title: String?; let total: Int? }
    struct Page: Decodable { let total: Int }
}
private struct SeasonMediaData: Decodable {
    let info: Info
    let medias: [LibraryArchive]?
    struct Info: Decodable { let title: String; let media_count: Int; let upper: LibraryArchive.Upper? }
}
private struct SeriesInfoData: Decodable {
    let meta: Meta
    struct Meta: Decodable { let mid: Int64; let name: String }
}
private struct SeriesArchivesData: Decodable {
    let archives: [LibraryArchive]
    let page: Page
    struct Page: Decodable { let total: Int }
}
