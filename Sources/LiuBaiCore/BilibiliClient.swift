import CryptoKit
import Foundation

public struct VideoReference: Equatable, Sendable {
    public let bvid: String?
    public let aid: String?
    public let page: Int

    public static func parse(_ input: String) throws -> VideoReference {
        let embeddedURL = input.range(of: "https?://[^\\s<>「」【】\"，。]+", options: .regularExpression).map { String(input[$0]) }
        let page = URLComponents(string: embeddedURL ?? input.trimmingCharacters(in: .whitespacesAndNewlines))?
            .queryItems?.first(where: { $0.name == "p" })?.value.flatMap(Int.init) ?? 1
        if let range = input.range(of: "(?i)(?<![a-z0-9])BV[a-z0-9]{10}(?![a-z0-9])", options: .regularExpression) {
            let value = String(input[range])
            return VideoReference(bvid: "BV" + value.dropFirst(2), aid: nil, page: max(1, page))
        }
        if let range = input.range(of: "(?i)(?<![a-z0-9])av[0-9]+(?![a-z0-9])", options: .regularExpression) {
            return VideoReference(bvid: nil, aid: String(input[range].dropFirst(2)), page: max(1, page))
        }
        throw BilibiliError.invalidInput
    }
}

public enum BilibiliError: LocalizedError {
    case invalidInput, invalidResponse, unavailable(String), noAudio, invalidPage, network(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidInput: return "请粘贴 B 站视频链接、BV 号或 av 号，也支持 b23.tv 分享链接。"
        case .invalidResponse: return "B 站返回了无法识别的数据，请稍后重试。"
        case .unavailable(let message): return message
        case .noAudio: return "这个视频没有可用的独立音频流。首版支持无需登录的公开视频。"
        case .invalidPage: return "链接中的分 P 不存在，请检查链接中的 p 参数。"
        case .network(let status): return "网络请求失败（HTTP \(status)），请稍后重试。"
        }
    }
}

public struct AudioStream: Sendable {
    public let urls: [URL]
    public let bandwidth: Int
    public let mimeType: String
    public init(urls: [URL], bandwidth: Int, mimeType: String) {
        self.urls = urls; self.bandwidth = bandwidth; self.mimeType = mimeType
    }
}

// WBI parameter ordering and key permutation follow wood3n/biu's protocol
// implementation. Attribution and its noncommercial license are in Notices/.
public enum WBISigner {
    private static let permutation = [
        46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,
        13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52
    ]
    public static func mixinKey(imageKey: String, subKey: String) throws -> String {
        let bytes = Array((imageKey + subKey).utf8)
        guard bytes.count >= 64 else { throw BilibiliError.invalidResponse }
        return String(decoding: permutation.prefix(32).map { bytes[$0] }, as: UTF8.self)
    }
    public static func query(_ parameters: [String: String], mixinKey: String, timestamp: Int) -> String {
        var values = parameters
        values["wts"] = String(timestamp)
        let forbidden = CharacterSet(charactersIn: "!'()*")
        let query = values.keys.sorted().map { key in
            let cleaned = values[key]!.components(separatedBy: forbidden).joined()
            return "\(encode(key))=\(encode(cleaned))"
        }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + mixinKey).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return query + "&w_rid=" + digest
    }
    public static func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? ""
    }
}

public actor BilibiliClient {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    public static let referer = "https://www.bilibili.com/"
    private let session: URLSession
    private var cachedKey: (key: String, fetchedAt: Date)?
    private var resolvedTracks: [String: Track] = [:]

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent, "Referer": Self.referer]
        session = URLSession(configuration: configuration)
    }

    public func resolve(_ input: String) async throws -> Track {
        let expanded = try await expandShortLink(input)
        let reference = try VideoReference.parse(expanded)
        var params: [String: String] = [:]
        if let bvid = reference.bvid { params["bvid"] = bvid }
        if let aid = reference.aid { params["aid"] = aid }
        let envelope: Envelope<VideoData> = try await request("/x/web-interface/view", parameters: params)
        try check(envelope.code, message: envelope.message)
        guard let video = envelope.data else { throw BilibiliError.invalidResponse }
        guard reference.page <= video.pages.count, let part = video.pages.first(where: { $0.page == reference.page }) else {
            throw BilibiliError.invalidPage
        }
        let title = video.pages.count > 1 ? "\(video.title) · P\(part.page) \(part.part)" : video.title
        let track = Track(bvid: video.bvid, cid: part.cid, title: title, artist: video.owner.name, duration: Double(part.duration), page: part.page)
        if resolvedTracks.count >= 256 { resolvedTracks.removeAll(keepingCapacity: true) }
        resolvedTracks[track.libraryKey] = track
        return track
    }

    /// Resolves fresh CDN URLs at playback time, rather than persisting expiring URLs.
    /// Only DASH audio is decoded; the video stream is never requested or rendered.
    public func audio(for track: Track) async throws -> AudioStream {
        // Collection imports retain small metadata records. Resolve the CID only
        // when this item is actually played; no audio is fetched during import.
        if track.cid <= 0 {
            let resolved: Track
            if let cached = resolvedTracks[track.libraryKey] { resolved = cached }
            else { resolved = try await resolve("https://www.bilibili.com/video/\(track.bvid)/?p=\(track.page ?? 1)") }
            return try await audio(for: resolved)
        }
        let key = try await signingKey()
        let params = ["bvid": track.bvid, "cid": String(track.cid), "fnval": "16", "fnver": "0", "fourk": "0", "gaia_source": "view-card"]
        let query = WBISigner.query(params, mixinKey: key, timestamp: Int(Date().timeIntervalSince1970))
        let envelope: Envelope<PlayData> = try await request("/x/player/wbi/playurl", encodedQuery: query)
        try check(envelope.code, message: envelope.message)
        guard let audio = envelope.data?.dash?.audio?
            .filter({ ($0.codecs ?? "mp4a").hasPrefix("mp4a") })
            .sorted(by: { ($0.bandwidth ?? 0) > ($1.bandwidth ?? 0) }).first else { throw BilibiliError.noAudio }
        var seenURLs = Set<URL>()
        let urls = ([audio.baseUrl ?? audio.base_url].compactMap { $0 } + (audio.backupUrl ?? audio.backup_url ?? []))
            .compactMap { URL(string: $0) }
            .filter { $0.scheme == "https" && seenURLs.insert($0).inserted }
        guard !urls.isEmpty else { throw BilibiliError.noAudio }
        return AudioStream(urls: urls, bandwidth: audio.bandwidth ?? 0, mimeType: audio.mimeType ?? audio.mime_type ?? "audio/mp4")
    }

    func signingKey() async throws -> String {
        if let cachedKey, Date().timeIntervalSince(cachedKey.fetchedAt) < 1800 { return cachedKey.key }
        let envelope: Envelope<NavigationData> = try await request("/x/web-interface/nav")
        // Logged-out navigation returns -101 but still supplies public WBI keys.
        guard let images = envelope.data?.wbi_img,
              let imageURL = URL(string: images.img_url), let subURL = URL(string: images.sub_url) else {
            throw BilibiliError.invalidResponse
        }
        let key = try WBISigner.mixinKey(imageKey: imageURL.deletingPathExtension().lastPathComponent,
                                        subKey: subURL.deletingPathExtension().lastPathComponent)
        cachedKey = (key, Date())
        return key
    }

    func request<T: Decodable>(_ path: String, parameters: [String: String] = [:], encodedQuery: String? = nil) async throws -> Envelope<T> {
        var components = URLComponents(string: "https://api.bilibili.com" + path)!
        if let encodedQuery { components.percentEncodedQuery = encodedQuery }
        else if !parameters.isEmpty { components.queryItems = parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw BilibiliError.invalidInput }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else { throw BilibiliError.invalidResponse }
        guard response.statusCode == 200 else { throw BilibiliError.network(response.statusCode) }
        do { return try JSONDecoder().decode(Envelope<T>.self, from: data) }
        catch { throw BilibiliError.invalidResponse }
    }

    func expandShortLink(_ input: String) async throws -> String {
        guard let range = input.range(of: "https?://(?:www\\.)?b23\\.tv/[A-Za-z0-9]+", options: .regularExpression),
              let url = URL(string: String(input[range])) else { return input }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let destination = response.url, let host = destination.host,
              host == "bilibili.com" || host.hasSuffix(".bilibili.com") else { throw BilibiliError.invalidInput }
        return destination.absoluteString
    }

    func check(_ code: Int, message: String?) throws {
        guard code != 0 else { return }
        switch code {
        case -101, -403: throw BilibiliError.unavailable("这个内容需要播放权限。收藏夹登录只用于读取列表；请添加无需登录的公开视频。")
        case -352, -412: throw BilibiliError.unavailable("B 站暂时限制了请求，请稍后重试。")
        case -404, 62002, 62004, 62012: throw BilibiliError.unavailable("这个视频暂时无法访问，可能已下架或设为私密。")
        default: throw BilibiliError.unavailable("B 站返回错误（\(code)）：\(message ?? "请稍后重试")")
        }
    }
}

struct Envelope<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?
}
struct VideoData: Decodable {
    let bvid: String
    let title: String
    let owner: Owner
    let pages: [Page]
    let ugc_season: Season?
    struct Owner: Decodable { let name: String; let mid: Int64? }
    struct Season: Decodable { let id: Int64; let mid: Int64?; let title: String? }
    struct Page: Decodable { let cid: Int64; let page: Int; let part: String; let duration: Int }
}
private struct NavigationData: Decodable {
    let wbi_img: Images?
    struct Images: Decodable { let img_url: String; let sub_url: String }
}
private struct PlayData: Decodable {
    let dash: Dash?
    struct Dash: Decodable { let audio: [Audio]? }
    struct Audio: Decodable {
        let baseUrl: String?
        let base_url: String?
        let backupUrl: [String]?
        let backup_url: [String]?
        let bandwidth: Int?
        let mimeType: String?
        let mime_type: String?
        let codecs: String?
    }
}
