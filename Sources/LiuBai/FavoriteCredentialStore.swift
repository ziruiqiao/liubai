import Foundation
import LiuBaiCore
import LocalAuthentication
import Security

/// Login credentials are never part of AppData, JSON backups, or exported diaries.
final class FavoriteCredentialStore {
    private let service: String
    private let account = "favorites-read-session"
    init() {
        let development = ProcessInfo.processInfo.environment["LIUBAI_DATA_DIR"] != nil
        service = "app.liubai.mac.favorites" + (development ? ".development" : "")
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func load() throws -> FavoritesSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        // Merely opening the page must not cause a Keychain access dialog.
        let context = LAContext()
        context.interactionNotAllowed = true
        lookup[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data else { throw CredentialError(status: status) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(FavoritesSession.self, from: bytes)
    }
    func save(_ session: FavoritesSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let bytes = try encoder.encode(session)
        let update = [kSecValueData as String: bytes]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = bytes
            item[kSecAttrLabel as String] = "留白 · B 站收藏夹连接"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialError(status: status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError(status: status) }
    }
    private struct CredentialError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "macOS 钥匙串暂时不可用（\(status)）。可以不勾选“记住登录”，只连接本次会话。" }
    }
}
