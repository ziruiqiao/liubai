import Foundation

public final class FileStore {
    public let directory: URL
    private let legacyDirectory: URL?
    public var fileURL: URL { directory.appendingPathComponent("liubai.json") }
    public var backupURL: URL { directory.appendingPathComponent("liubai.backup.json") }

    public init(directory: URL? = nil, legacyDirectory: URL? = nil) {
        self.legacyDirectory = legacyDirectory
        if let directory { self.directory = directory }
        else if let override = ProcessInfo.processInfo.environment["LIUBAI_DATA_DIR"] {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LiuBai", isDirectory: true)
        }
    }
    public func load() throws -> AppData {
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        let source = exists ? fileURL : legacyDirectory?.appendingPathComponent("liubai.json")
        guard let source, FileManager.default.fileExists(atPath: source.path) else { return AppData() }
        var result = try Self.decode(Data(contentsOf: source))
        guard result.version == 1 else { throw StoreError.unsupportedVersion }
        // 0.1 enabled automatic pausing by default. Upgrade existing installs to
        // continuous playback once, then preserve explicit future opt-ins.
        if result.musicContinuityRevision == nil {
            result.preferences.pauseMusicDuringBreak = false
            result.musicContinuityRevision = 1
        }
        let migratedMusic = result.migrateMusicMembership()
        if !exists || migratedMusic { try save(result) }
        return result
    }
    public func save(_ data: AppData) throws {
        let encoded = try Self.encode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            // Never replace a valid backup with corrupted data.
            _ = try Self.decode(previous)
            try previous.write(to: backupURL, options: .atomic)
        }
        try encoded.write(to: fileURL, options: .atomic)
    }
    public static func encode(_ data: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(data)
    }
    public static func decode(_ bytes: Data) throws -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(AppData.self, from: bytes)
    }
    public enum StoreError: LocalizedError {
        case unsupportedVersion
        public var errorDescription: String? { "数据来自更新版本的留白，请使用更新版本打开。" }
    }
}
