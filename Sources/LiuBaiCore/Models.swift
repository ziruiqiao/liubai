import Foundation

public struct Track: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(bvid)-\(cid)" }
    /// Stable for metadata-only imports, before a video's CID is resolved.
    public var libraryKey: String { "\(bvid)-p\(page ?? 1)" }
    public var bvid: String
    public var cid: Int64
    public var title: String
    public var artist: String
    public var duration: TimeInterval
    public var addedAt: Date
    public var page: Int?

    public init(bvid: String, cid: Int64, title: String, artist: String, duration: TimeInterval, addedAt: Date = Date(), page: Int? = nil) {
        self.bvid = bvid; self.cid = cid; self.title = title
        self.artist = artist; self.duration = duration; self.addedAt = addedAt
        self.page = page
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var roundsBeforeLongBreak = 4
    public var pauseMusicDuringBreak = false
    public var autoStartBreak = false
    public var autoStartFocus = false
    public var soundEnabled = true
    public var repeatTrack = false
    public var volume: Float = 0.65
    public init() {}

    public func duration(for phase: TimerPhase) -> TimeInterval {
        switch phase {
        case .focus: return Double(min(180, max(1, focusMinutes))) * 60
        case .shortBreak: return Double(min(60, max(1, shortBreakMinutes))) * 60
        case .longBreak: return Double(min(90, max(1, longBreakMinutes))) * 60
        }
    }
}

public enum TimerPhase: String, Codable, CaseIterable, Sendable {
    case focus, shortBreak, longBreak
    public var title: String {
        switch self { case .focus: return "专注"; case .shortBreak: return "短休息"; case .longBreak: return "长休息" }
    }
}

public struct DailyStats: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var usageSeconds: TimeInterval = 0
    public var listeningSeconds: TimeInterval = 0
    public var focusSeconds: TimeInterval = 0
    public var completedRounds = 0
    public var usedPomodoro = false
    public init(id: String) { self.id = id }
}

public struct JournalEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title = ""
    public var body = ""
    public var mood = "平静"
    public var updatedAt: Date
    public init(id: String, updatedAt: Date = Date()) { self.id = id; self.updatedAt = updatedAt }
    public var hasContent: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct AppData: Codable, Sendable {
    public var version = 1
    public var tracks: [Track] = []
    public var preferences = Preferences()
    public var dailyStats: [String: DailyStats] = [:]
    public var journal: [String: JournalEntry] = [:]
    public var timer = PomodoroEngine()
    public var intention = ""
    // Optional so existing version-1 documents remain readable without migration.
    public var collections: [LibraryCollection]?
    // Membership is separate from the shared metadata index in `tracks`.
    // nil identifies documents written before individual imports were tracked.
    public var myMusicKeys: [String]? = []
    public var musicContinuityRevision: Int? = 1
    public var weatherEnabled: Bool?
    public var focusBlocks: [FocusBlock]?
    public var activeFocusBlockID: UUID?
    public var usesWeather: Bool { weatherEnabled ?? true }
    public init() {}
}

public enum DayKey {
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

public enum TimeText {
    public static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if seconds > 0 && minutes == 0 { return "不足 1 分钟" }
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
}
