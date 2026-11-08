import Foundation

public enum LibrarySourceKind: String, Codable, Sendable {
    case season, series, parts, favorites
    public var title: String {
        switch self { case .season: return "UP 主合集"; case .series: return "UP 主系列"; case .parts: return "分 P 合集"; case .favorites: return "收藏夹" }
    }
}

public struct LibraryCollection: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: LibrarySourceKind
    public var sourceURL: String
    public var trackKeys: [String]
    public var importedAt: Date
    public init(id: String, title: String, kind: LibrarySourceKind, sourceURL: String, trackKeys: [String], importedAt: Date = Date()) {
        self.id = id; self.title = title; self.kind = kind; self.sourceURL = sourceURL
        self.trackKeys = trackKeys; self.importedAt = importedAt
    }
}

public struct LibraryPreview: Sendable {
    public var id: String
    public var title: String
    public var kind: LibrarySourceKind
    public var sourceURL: String
    public var tracks: [Track]
    public var skippedCount: Int
    public init(id: String, title: String, kind: LibrarySourceKind, sourceURL: String, tracks: [Track], skippedCount: Int = 0) {
        self.id = id; self.title = title; self.kind = kind; self.sourceURL = sourceURL
        self.tracks = tracks; self.skippedCount = skippedCount
    }
}

public enum CollectionReference: Equatable, Sendable {
    case season(id: Int64, ownerID: Int64?)
    case series(id: Int64, ownerID: Int64?)
    case video(VideoReference)

    public static func parse(_ input: String) throws -> CollectionReference {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = text.range(of: "https?://[^\\s<>「」【】\"，。]+", options: .regularExpression)
        let urlText = match.map { String(text[$0]) } ?? text
        if let url = URLComponents(string: urlText), let host = url.host?.lowercased(),
           host == "bilibili.com" || host.hasSuffix(".bilibili.com") {
            let parts = url.path.split(separator: "/").map(String.init)
            let query = Dictionary(url.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { first, _ in first })
            let owner = parts.first.flatMap(Int64.init)
            if host == "space.bilibili.com", parts.count >= 3, parts[1] == "lists", let id = Int64(parts[2]), id > 0, let owner, owner > 0 {
                return query["type"] == "series" ? .series(id: id, ownerID: owner) : .season(id: id, ownerID: owner)
            }
            if host == "space.bilibili.com", let id = query["sid"].flatMap(Int64.init), id > 0 {
                if parts.contains("seriesdetail") { return .series(id: id, ownerID: owner) }
                if parts.contains("collectiondetail") { return .season(id: id, ownerID: owner) }
            }
            if let id = query["business_id"].flatMap(Int64.init), id > 0 {
                if query["business"] == "space_collection" { return .season(id: id, ownerID: nil) }
                if query["business"] == "space_series" { return .series(id: id, ownerID: nil) }
            }
            if let id = query["season_id"].flatMap(Int64.init), id > 0 { return .season(id: id, ownerID: owner) }
        }
        do { return .video(try VideoReference.parse(text)) }
        catch { throw BilibiliError.unavailable("请粘贴 UP 主的合集 / 系列地址，或一个多分 P、属于合集的视频链接。") }
    }
}

/// Deduplicates page boundaries while refusing silently repeated/truncated pages.
public struct LibraryPageAccumulator {
    public private(set) var tracks: [Track] = []
    private var keys = Set<String>()
    public init() {}
    public mutating func append(_ page: [Track], hasMore: Bool) throws {
        var added = 0
        for track in page where keys.insert(track.libraryKey).inserted { tracks.append(track); added += 1 }
        if hasMore && added == 0 { throw BilibiliError.unavailable("列表分页没有继续返回新内容，请稍后重新读取。尚未导入任何音乐。") }
    }
}
