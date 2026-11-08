import Foundation

public enum FavoritesError: LocalizedError {
    case signedOut, expired, forbiddenRequest, missingCredentials, emptyFolder, unsupportedLoginStatus
    public var errorDescription: String? {
        switch self {
        case .signedOut: return "请先扫码登录，再读取你创建的收藏夹。"
        case .expired: return "收藏夹登录已过期，请重新扫码。"
        case .forbiddenRequest: return "这项请求不在收藏夹只读访问范围内。"
        case .missingCredentials: return "B 站没有返回完整的登录信息，请重新扫码。"
        case .emptyFolder: return "这个收藏夹还没有可加入的视频。"
        case .unsupportedLoginStatus: return "登录状态暂时无法识别，请刷新二维码。"
        }
    }
}

public struct FavoritesSession: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let userID: Int64
    public let expiresAt: Date
    private let sessionToken: String
    public var description: String { "FavoritesSession(<redacted>)" }
    public var debugDescription: String { description }
    public init(userID: Int64, sessionToken: String, expiresAt: Date) throws {
        guard userID > 0, !sessionToken.isEmpty, sessionToken.utf8.count < 4096,
              sessionToken.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 && $0 != ";" }) else {
            throw FavoritesError.missingCredentials
        }
        self.userID = userID; self.sessionToken = sessionToken; self.expiresAt = expiresAt
    }
    fileprivate var cookieHeader: String { "SESSDATA=\(sessionToken); DedeUserID=\(userID)" }
    public var isExpired: Bool { expiresAt <= Date() }
    private enum CodingKeys: String, CodingKey { case userID, sessionToken, expiresAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(userID: values.decode(Int64.self, forKey: .userID), sessionToken: values.decode(String.self, forKey: .sessionToken), expiresAt: values.decode(Date.self, forKey: .expiresAt))
    }

    /// Extract just identity and session cookies. No CSRF token or refresh token
    /// is kept, since this client has no account mutation or refresh endpoints.
    public static func fromLogin(response: HTTPURLResponse, callbackURL: String, now: Date = Date()) throws -> FavoritesSession {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: URL(string: "https://passport.bilibili.com/")!)
        let query = URLComponents(string: callbackURL)?.queryItems ?? []
        func value(_ name: String) -> String? {
            cookies.first(where: { $0.name == name })?.value ?? query.first(where: { $0.name == name })?.value
        }
        guard let uid = value("DedeUserID").flatMap(Int64.init), let token = value("SESSDATA") else { throw FavoritesError.missingCredentials }
        let expiry = cookies.first(where: { $0.name == "SESSDATA" })?.expiresDate ?? now.addingTimeInterval(180 * 86400)
        return try FavoritesSession(userID: uid, sessionToken: token, expiresAt: expiry)
    }
}

public enum FavoritesReadPolicy {
    public static let paths: Set<String> = ["/x/v3/fav/folder/created/list-all", "/x/v3/fav/resource/list"]
    public static func validate(_ request: URLRequest) throws {
        guard request.httpMethod == "GET", let url = request.url, url.scheme == "https",
              url.host == "api.bilibili.com", paths.contains(url.path), url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { throw FavoritesError.forbiddenRequest }
    }
}

public struct FavoriteFolder: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let title: String
    public let count: Int
    public let isPrivate: Bool
    public init(id: Int64, title: String, count: Int, isPrivate: Bool) {
        self.id = id; self.title = title; self.count = count; self.isPrivate = isPrivate
    }
}

public struct LoginChallenge: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let url: String
    fileprivate let key: String
    public var description: String { "LoginChallenge(<redacted>)" }
    public var debugDescription: String { description }
}

public enum LoginPollResult: Sendable {
    case waiting, scanned, expired, success(FavoritesSession)
}

public protocol FavoritesTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class FavoritesNetworkTransport: FavoritesTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration, delegate: NoFavoritesRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, allowed(url), request.httpMethod == "GET" else { throw FavoritesError.forbiddenRequest }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BilibiliError.invalidResponse }
        guard http.statusCode == 200 else { throw BilibiliError.network(http.statusCode) }
        return (bytes, http)
    }
    private func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        if url.host == "api.bilibili.com" { return FavoritesReadPolicy.paths.contains(url.path) }
        return url.host == "passport.bilibili.com" && ["/x/passport-login/web/qrcode/generate", "/x/passport-login/web/qrcode/poll"].contains(url.path)
    }
}

private final class NoFavoritesRedirects: NSObject, URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // These four JSON endpoints do not need redirects. Never forward a
        // cookie or QR nonce to another URL, even within the same host.
        completionHandler(nil)
    }
}

/// The authenticated client is deliberately separate from music playback and
/// collection parsing. Its only authenticated operations are the two GETs above.
public actor FavoritesClient {
    private let transport: any FavoritesTransport
    private var session: FavoritesSession?
    private var ownedFolderIDs = Set<Int64>()
    private var generation = UUID()
    public init(transport: any FavoritesTransport = FavoritesNetworkTransport()) { self.transport = transport }

    @discardableResult
    public func connect(_ session: FavoritesSession) throws -> UUID {
        try Task.checkCancellation()
        guard !session.isExpired else { throw FavoritesError.expired }
        self.session = session; ownedFolderIDs.removeAll(); generation = UUID()
        return generation
    }
    public func disconnect(ifMatches expected: UUID? = nil) {
        if let expected, expected != generation { return }
        session = nil; ownedFolderIDs.removeAll(); generation = UUID()
    }

    public func beginLogin() async throws -> LoginChallenge {
        let (bytes, _) = try await transport.data(for: request(host: "passport.bilibili.com", path: "/x/passport-login/web/qrcode/generate"))
        let result = try JSONDecoder().decode(Envelope<GenerateData>.self, from: bytes)
        try check(result.code, message: result.message)
        guard let data = result.data, !data.qrcode_key.isEmpty,
              let url = URL(string: data.url), url.scheme == "https",
              ["account.bilibili.com", "passport.bilibili.com", "www.bilibili.com"].contains(url.host ?? "") else { throw BilibiliError.invalidResponse }
        return LoginChallenge(url: data.url, key: data.qrcode_key)
    }
    public func poll(_ challenge: LoginChallenge) async throws -> LoginPollResult {
        let (bytes, response) = try await transport.data(for: request(host: "passport.bilibili.com", path: "/x/passport-login/web/qrcode/poll", parameters: ["qrcode_key": challenge.key]))
        let result = try JSONDecoder().decode(Envelope<PollData>.self, from: bytes)
        try check(result.code, message: result.message)
        guard let data = result.data else { throw BilibiliError.invalidResponse }
        switch data.code {
        case 86101: return .waiting
        case 86090: return .scanned
        case 86038: return .expired
        case 0: return .success(try FavoritesSession.fromLogin(response: response, callbackURL: data.url ?? ""))
        default: throw FavoritesError.unsupportedLoginStatus
        }
    }

    public func folders() async throws -> [FavoriteFolder] {
        guard let session, !session.isExpired else { throw FavoritesError.signedOut }
        let current = generation
        let result: FolderData = try await authenticated("/x/v3/fav/folder/created/list-all", parameters: ["up_mid": String(session.userID), "type": "2"])
        guard current == generation else { throw CancellationError() }
        let folders = (result.list ?? []).map { FavoriteFolder(id: $0.id, title: $0.title, count: $0.media_count, isPrivate: $0.attr & 1 == 1) }
        ownedFolderIDs = Set(folders.map(\.id))
        return folders
    }

    public func contents(of folder: FavoriteFolder, progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> LibraryPreview {
        guard let session, !session.isExpired else { throw FavoritesError.signedOut }
        if !ownedFolderIDs.contains(folder.id) { _ = try await folders() }
        guard ownedFolderIDs.contains(folder.id) else { throw FavoritesError.forbiddenRequest }
        let current = generation
        var page = 1
        var result = LibraryPageAccumulator()
        var skipped = 0
        var seenRawItems = Set<String>()
        while true {
            try Task.checkCancellation()
            let data: FolderContentsData = try await authenticated("/x/v3/fav/resource/list", parameters: ["media_id": String(folder.id), "pn": String(page), "ps": "20", "order": "mtime", "platform": "web", "type": "0"])
            guard generation == current else { throw CancellationError() }
            let medias = data.medias ?? []
            let newItems = medias.reduce(0) { $0 + (seenRawItems.insert($1.rawKey).inserted ? 1 : 0) }
            if data.has_more && newItems == 0 { throw BilibiliError.unavailable("收藏夹分页没有继续返回新内容，请重新读取。") }
            let tracks = medias.compactMap { $0.track(artist: $0.upper?.name ?? "收藏夹音乐") }
            skipped += medias.count - tracks.count
            // Pages containing only deleted entries are valid; raw page identity
            // still has to advance before another page is requested.
            if medias.isEmpty && data.has_more { throw BilibiliError.unavailable("收藏夹分页未返回内容，请重新读取。") }
            try result.append(tracks, hasMore: data.has_more && !tracks.isEmpty)
            await progress(result.tracks.count, data.info.media_count)
            if !data.has_more {
                return LibraryPreview(id: "favorite:\(folder.id)", title: data.info.title, kind: .favorites,
                                      sourceURL: "https://space.bilibili.com/\(session.userID)/favlist?fid=\(folder.id)", tracks: result.tracks, skippedCount: skipped)
            }
            page += 1
            if page > 10000 { throw BilibiliError.unavailable("收藏夹分页异常，已停止读取。") }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func authenticated<T: Decodable>(_ path: String, parameters: [String: String]) async throws -> T {
        guard let session else { throw FavoritesError.signedOut }
        guard !session.isExpired else { throw FavoritesError.expired }
        let current = generation
        var request = request(host: "api.bilibili.com", path: path, parameters: parameters)
        try FavoritesReadPolicy.validate(request)
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        let (bytes, _) = try await transport.data(for: request)
        guard current == generation else { throw CancellationError() }
        let result = try JSONDecoder().decode(Envelope<T>.self, from: bytes)
        try check(result.code, message: result.message)
        guard let data = result.data else { throw BilibiliError.invalidResponse }
        return data
    }
    private func request(host: String, path: String, parameters: [String: String] = [:]) -> URLRequest {
        var url = URLComponents(string: "https://\(host)\(path)")!
        if !parameters.isEmpty { url.queryItems = parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: url.url!)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(BilibiliClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BilibiliClient.referer, forHTTPHeaderField: "Referer")
        return request
    }
    private func check(_ code: Int, message: String?) throws {
        if code == -101 || code == -111 || code == -403 { session = nil; ownedFolderIDs.removeAll(); generation = UUID(); throw FavoritesError.expired }
        guard code == 0 else {
            if code == -352 || code == -412 { throw BilibiliError.unavailable("B 站暂时限制了请求，请稍后重试。") }
            throw BilibiliError.unavailable("收藏夹请求失败（\(code)）：\(message ?? "请稍后重试")")
        }
    }
}

private struct GenerateData: Decodable { let url: String; let qrcode_key: String }
private struct PollData: Decodable { let code: Int; let url: String? }
private struct FolderData: Decodable {
    let list: [Folder]?
    struct Folder: Decodable { let id: Int64; let title: String; let media_count: Int; let attr: Int }
}
private struct FolderContentsData: Decodable {
    let info: Info
    let medias: [LibraryArchive]?
    let has_more: Bool
    struct Info: Decodable { let title: String; let media_count: Int }
}
