import Combine
import Foundation
import LiuBaiCore

@MainActor
final class FavoritesController: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var folders: [FavoriteFolder] = []
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var storageNotice: String?
    @Published var showLogin = false
    @Published var challenge: LoginChallenge?
    @Published var loginStatus = ""
    @Published var loginExpired = false
    @Published var loginWorking = false
    @Published var rememberLogin = true
    let client = FavoritesClient()
    private let credentials = FavoriteCredentialStore()
    private var loginTask: Task<Void, Never>?
    private var foldersTask: Task<Void, Never>?
    private var loginID = UUID()
    private var accountID = UUID()
    private var didRestore = false

    func restoreAndLoad() {
        guard !didRestore else { return }
        didRestore = true
        foldersTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let session = try credentials.load(), !session.isExpired else { return }
                try await client.connect(session)
                isConnected = true
                await loadFolders()
            } catch { self.error = error.localizedDescription }
        }
    }
    func refresh() {
        guard !isLoading, isConnected else { return }
        foldersTask?.cancel()
        foldersTask = Task { [weak self] in await self?.loadFolders() }
    }
    private func loadFolders() async {
        let id = accountID
        isLoading = true; error = nil
        defer { if id == accountID { isLoading = false } }
        do {
            let result = try await client.folders()
            guard !Task.isCancelled, id == accountID else { return }
            folders = result
        } catch {
            guard !Task.isCancelled, id == accountID else { return }
            handle(error)
        }
    }
    func beginLogin() {
        cancelLogin()
        let id = UUID()
        loginID = id
        challenge = nil; loginExpired = false; loginWorking = true; loginStatus = "正在生成二维码…"; error = nil
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await client.beginLogin()
                guard !Task.isCancelled, loginID == id else { return }
                challenge = code; loginStatus = "用哔哩哔哩手机 App 扫码"; loginWorking = false
                let deadline = Date().addingTimeInterval(180)
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(2))
                    let result = try await client.poll(code)
                    guard !Task.isCancelled, loginID == id else { return }
                    switch result {
                    case .waiting: loginStatus = "用哔哩哔哩手机 App 扫码"
                    case .scanned: loginStatus = "已扫码，请在手机上确认登录"
                    case .expired: loginExpired = true; loginStatus = "二维码已失效，点击刷新"; return
                    case .success(let session):
                        let connection = try await client.connect(session)
                        guard !Task.isCancelled, loginID == id else { await client.disconnect(ifMatches: connection); return }
                        if rememberLogin {
                            do { try credentials.save(session); storageNotice = nil }
                            catch { storageNotice = "本次已连接，但登录未能存入钥匙串。退出 App 后需重新扫码。" }
                        } else {
                            // An explicit session-only login replaces any prior remembered login.
                            do { try credentials.remove(); storageNotice = "仅本次会话连接，退出 App 后需重新扫码。" }
                            catch { storageNotice = error.localizedDescription }
                        }
                        isConnected = true; challenge = nil; loginStatus = "已连接收藏夹"
                        accountID = UUID()
                        refresh()
                        showLogin = false
                        return
                    }
                }
                loginExpired = true; loginStatus = "二维码已失效，点击刷新"
            } catch {
                guard !Task.isCancelled, loginID == id else { return }
                loginWorking = false; loginExpired = true; loginStatus = error.localizedDescription
            }
        }
    }
    func cancelLogin() {
        loginTask?.cancel(); loginTask = nil; loginID = UUID(); challenge = nil; loginWorking = false
    }
    func disconnect() {
        cancelLogin(); foldersTask?.cancel(); foldersTask = nil
        accountID = UUID(); isConnected = false; folders = []; isLoading = false; error = nil; storageNotice = nil
        Task { await client.disconnect() }
        do { try credentials.remove() }
        catch { self.error = "会话已断开，但钥匙串条目尚未移除。\(error.localizedDescription)" }
    }
    func handle(_ failure: Error) {
        if case FavoritesError.expired = failure { isConnected = false; folders = [] }
        if case FavoritesError.signedOut = failure { isConnected = false; folders = [] }
        error = failure.localizedDescription
    }
}
