import Foundation
import LiuBaiCore

enum LibraryChecks {
    static func run() async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw LibraryCheckError(message: message) }
            count += 1
        }
        let reference = try CollectionReference.parse("https://space.bilibili.com/1252412810/lists/8996743?type=season")
        try check(reference == .season(id: 8996743, ownerID: 1252412810), "The provided season URL must retain creator and collection IDs")
        let series = try CollectionReference.parse("https://space.bilibili.com/42/lists/123?type=series")
        try check(series == .series(id: 123, ownerID: 42), "Series links must use the series API, not the season API")
        let legacy = try CollectionReference.parse("https://space.bilibili.com/42/channel/collectiondetail?sid=123")
        try check(legacy == .season(id: 123, ownerID: 42), "Legacy collection links must remain supported")
        let medialist = try CollectionReference.parse("https://www.bilibili.com/medialist/play/42?business=space_collection&business_id=123")
        try check(medialist == .season(id: 123, ownerID: nil), "Shared medialist links must identify the season")
        func track(_ index: Int) -> Track { Track(bvid: String(format: "BV%010d", index), cid: 0, title: "音乐 \(index)", artist: "UP", duration: 600, page: 1) }
        var pages = LibraryPageAccumulator()
        try pages.append((1...30).map(track), hasMore: true)
        try pages.append((30...59).map(track), hasMore: true)
        try pages.append([track(60)], hasMore: false)
        try check(pages.tracks.count == 60 && pages.tracks.last?.bvid == track(60).bvid, "Pagination must collect later pages while deduplicating boundaries")
        var stalled = false
        do { try pages.append([track(60)], hasMore: true) } catch { stalled = true }
        try check(stalled, "A repeated page must stop rather than loop forever")
        let eager = Track(bvid: track(1).bvid, cid: 99, title: "音乐", artist: "UP", duration: 600, page: 1)
        try check(eager.libraryKey == track(1).libraryKey, "Lazy and individually resolved entries must deduplicate")
        let secondPart = Track(bvid: eager.bvid, cid: 100, title: "P2", artist: "UP", duration: 600, page: 2)
        try check(secondPart.libraryKey != eager.libraryKey, "Different video parts must remain separate songs")

        let session = try FavoritesSession(userID: 42, sessionToken: "fixture-secret%2Ctoken", expiresAt: Date().addingTimeInterval(3600))
        try check(!String(describing: session).contains("fixture-secret") && !String(reflecting: session).contains("fixture-secret"), "Debug descriptions must redact session credentials")
        var injectionRejected = false
        do { _ = try FavoritesSession(userID: 42, sessionToken: "x; injected=1", expiresAt: Date()) } catch { injectionRejected = true }
        try check(injectionRejected, "Cookie header injection must be rejected")
        for (url, method) in [
            ("https://api.bilibili.com/x/web-interface/nav", "GET"),
            ("https://api.bilibili.com/x/web-interface/archive/like", "POST"),
            ("https://api.bilibili.com/x/v3/fav/resource/list", "POST"),
            ("http://api.bilibili.com/x/v3/fav/resource/list", "GET"),
            ("https://api.bilibili.com.evil.invalid/x/v3/fav/resource/list", "GET")
        ] {
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = method
            var refused = false
            do { try FavoritesReadPolicy.validate(request) } catch { refused = true }
            try check(refused, "Authenticated access must reject \(method) \(url)")
        }

        var saved = AppData()
        saved.tracks = [track(1)]
        saved.collections = [LibraryCollection(id: "season:123", title: "音乐合集", kind: .season, sourceURL: "https://space.bilibili.com/42/lists/123?type=season", trackKeys: [track(1).libraryKey])]
        let bytes = try FileStore.encode(saved)
        let decoded = try FileStore.decode(bytes)
        try check(decoded.collections?.first?.trackKeys == saved.collections?.first?.trackKeys, "Local collection membership must survive a disk-format round trip")
        try check(!String(decoding: bytes, as: UTF8.self).contains("fixture-secret") && !String(decoding: bytes, as: UTF8.self).contains("SESSDATA"), "Exported app data must never include login credentials")
        var older = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        older.removeValue(forKey: "collections")
        let migrated = try FileStore.decode(JSONSerialization.data(withJSONObject: older))
        try check(migrated.tracks.count == 1 && migrated.collections == nil, "Version-1 data without collections must remain readable")
        try check(!Preferences().pauseMusicDuringBreak, "Timer completion must keep music playing by default")
        let migrationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("liubai-continuity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: migrationDirectory) }
        let migrationStore = FileStore(directory: migrationDirectory)
        var oldSettings = AppData()
        oldSettings.preferences.pauseMusicDuringBreak = true
        oldSettings.musicContinuityRevision = nil
        try migrationStore.save(oldSettings)
        var upgraded = try migrationStore.load()
        try check(!upgraded.preferences.pauseMusicDuringBreak && upgraded.musicContinuityRevision == 1, "Existing 0.1 defaults must migrate to uninterrupted music")
        upgraded.preferences.pauseMusicDuringBreak = true
        try migrationStore.save(upgraded)
        let explicitSetting = try migrationStore.load()
        try check(explicitSetting.preferences.pauseMusicDuringBreak, "A deliberate later opt-in to auto-pause must be preserved")
        let newStore = FileStore(directory: migrationDirectory.appendingPathComponent("release"), legacyDirectory: migrationDirectory)
        let fromPreviousApp = try newStore.load()
        try check(fromPreviousApp.preferences.pauseMusicDuringBreak && FileManager.default.fileExists(atPath: newStore.fileURL.path), "First release launch must retain the previous App's data without moving its source")
        var newer = fromPreviousApp
        newer.intention = "保留新版本记录"
        try newStore.save(newer)
        let keptNewer = try newStore.load()
        try check(keptNewer.intention == "保留新版本记录", "Existing release data must take precedence over an older source")

        let folderResponse: [String: Any] = ["code": 0, "message": "0", "data": ["list": [["id": 100, "title": "我的音乐", "media_count": 21, "attr": 1]]]]
        func media(_ index: Int) -> [String: Any] {
            ["bvid": track(index).bvid, "title": "音乐 \(index)", "duration": 600, "type": 2, "attr": 0, "upper": ["name": "UP", "mid": 7]]
        }
        func content(_ entries: [[String: Any]], more: Bool) -> [String: Any] {
            ["code": 0, "message": "0", "data": ["info": ["title": "我的音乐", "media_count": 21], "medias": entries, "has_more": more]]
        }
        let transport = FixtureFavoritesTransport(responses: [folderResponse, content((1...20).map(media), more: true), content([media(21)], more: false)])
        let client = FavoritesClient(transport: transport)
        try await client.connect(session)
        let folders = try await client.folders()
        try check(folders.count == 1 && folders[0].isPrivate, "Private folders must be retained for the signed-in user")
        let preview = try await client.contents(of: folders[0])
        try check(preview.tracks.count == 21 && preview.tracks.allSatisfy { $0.cid == 0 }, "Favorites must paginate beyond 20 and import metadata without fetching audio")
        let requests = await transport.recorded()
        try check(requests.count == 3 && requests.allSatisfy { $0.httpMethod == "GET" && FavoritesReadPolicy.paths.contains($0.url!.path) }, "Every authenticated call must be a whitelisted read-only favorites request")
        try check(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie")?.contains("fixture-secret") == true }, "Credentials must reach the favorites reads")
        try check(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "up_mid" })?.value == "42", "Folder ownership must use the signed-in UID")
        await client.disconnect()
        var logoutRefused = false
        do { _ = try await client.folders() } catch { logoutRefused = true }
        let afterLogout = await transport.recorded().count
        try check(logoutRefused && afterLogout == requests.count, "Disconnect must prevent all further authenticated network requests")

        let qrTransport = FixtureFavoritesTransport(responses: [
            ["code": 0, "data": ["url": "https://account.bilibili.com/h5-app/passport/login/scan?fixture=1", "qrcode_key": "fixture-nonce"]],
            ["code": 0, "data": ["code": 86101, "url": ""]],
            ["code": 0, "data": ["code": 86090, "url": ""]],
            ["code": 0, "data": ["code": 86038, "url": ""]]
        ])
        let qrClient = FavoritesClient(transport: qrTransport)
        try await qrClient.connect(session)
        let challenge = try await qrClient.beginLogin()
        if case .waiting = try await qrClient.poll(challenge) { try check(true, "Waiting QR") } else { try check(false, "QR must report waiting") }
        if case .scanned = try await qrClient.poll(challenge) { try check(true, "Scanned QR") } else { try check(false, "QR must wait for mobile confirmation") }
        if case .expired = try await qrClient.poll(challenge) { try check(true, "Expired QR") } else { try check(false, "QR must report expiry") }
        let qrRequests = await qrTransport.recorded()
        try check(qrRequests.allSatisfy { $0.url?.host == "passport.bilibili.com" && $0.value(forHTTPHeaderField: "Cookie") == nil }, "QR requests must never receive saved account credentials")
        let response = HTTPURLResponse(url: URL(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/poll")!, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": "SESSDATA=fixture-cookie; Path=/; Domain=.bilibili.com; Secure"])!
        let fromPoll = try FavoritesSession.fromLogin(response: response, callbackURL: "https://passport.biligame.com/crossDomain?DedeUserID=42&SESSDATA=fixture-query")
        try check(fromPoll.userID == 42, "Confirmed login must extract UID and session from the returned cookies/callback")
        let confirmedTransport = FixtureFavoritesTransport(responses: [
            ["code": 0, "data": ["url": "https://account.bilibili.com/h5-app/passport/login/scan?fixture=1", "qrcode_key": "fixture-nonce"]],
            ["code": 0, "data": ["code": 0, "url": "https://passport.biligame.com/crossDomain?DedeUserID=42&SESSDATA=fixture-confirmed%252Ctoken"]]
        ])
        let confirmedClient = FavoritesClient(transport: confirmedTransport)
        let confirmedChallenge = try await confirmedClient.beginLogin()
        if case .success(let credentials) = try await confirmedClient.poll(confirmedChallenge) {
            try check(credentials.userID == 42, "A confirmed scan must produce a validated favorites session")
        } else { try check(false, "A confirmed scan must complete login") }
        let connectionTransport = FixtureFavoritesTransport(responses: [folderResponse])
        let connectionClient = FavoritesClient(transport: connectionTransport)
        let previousConnection = try await connectionClient.connect(session)
        let nextSession = try FavoritesSession(userID: 43, sessionToken: "fixture-new-session", expiresAt: Date().addingTimeInterval(3600))
        try await connectionClient.connect(nextSession)
        await connectionClient.disconnect(ifMatches: previousConnection)
        _ = try await connectionClient.folders()
        let afterCancelledLogin = await connectionTransport.recorded()
        try check(afterCancelledLogin.first?.value(forHTTPHeaderField: "Cookie")?.contains("fixture-new-session") == true,
                  "Cancelling an old login must not disconnect a newer account session")
        return count
    }
}

private struct LibraryCheckError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private actor FixtureFavoritesTransport: FavoritesTransport {
    private var responses: [[String: Any]]
    private var requests: [URLRequest] = []
    init(responses: [[String: Any]]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !responses.isEmpty else { throw LibraryCheckError(message: "Unexpected network request") }
        requests.append(request)
        return (try JSONSerialization.data(withJSONObject: responses.removeFirst()), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func recorded() -> [URLRequest] { requests }
}
