import Foundation
import LiuBaiCore

enum PomodoroJournalChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw NSError(domain: "PomodoroJournalChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            count += 1
        }
        let start = Date(timeIntervalSince1970: 1_000_000)
        for automaticFocus in [false, true] {
            for automaticCycle in [false, true] {
                var preferences = Preferences()
                preferences.autoStartFocus = automaticFocus
                preferences.autoStartCycle = automaticCycle
                for phase in [TimerPhase.shortBreak, .longBreak] {
                    var timer = PomodoroEngine()
                    timer.select(phase, preferences: preferences)
                    timer.start(at: start)
                    let end = start.addingTimeInterval(preferences.duration(for: phase) + 1)
                    let completion = timer.advance(to: end, preferences: preferences)
                    try check(completion?.phase == phase && timer.phase == .focus, "A completed break must prepare the next focus phase")
                    try check(timer.isRunning == (phase == .longBreak ? automaticCycle : automaticFocus), "Short-break and long-break automatic starts must be independent")
                    try check(timer.secondsRemaining(at: end) == preferences.duration(for: .focus), "Waiting after a break must retain a full focus duration")
                    try check(timer.advance(to: end, preferences: preferences) == nil, "Break completion must only be delivered once")
                }
            }
        }
        var original = Preferences()
        original.autoStartFocus = true
        original.focusMinutes = 42
        original.volume = 0.37
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "autoStartCycle")
        legacy.removeValue(forKey: "chimeVolume")
        let upgraded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        try check(upgraded.autoStartFocus && !upgraded.autoStartCycle && upgraded.chimeVolume == 0.65, "Old preferences must retain short-break behavior and default to waiting after long breaks")
        try check(upgraded.focusMinutes == 42 && upgraded.volume == 0.37, "Upgrades must retain existing durations and music volume")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liubai-mood-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = FileStore(directory: directory)
        var data = AppData()
        try check(data.registerMood("  有点期待  ") == "有点期待", "Custom moods must trim surrounding whitespace")
        try check(data.registerMood("有点期待") == "有点期待" && data.availableMoods.count == 5, "Repeated saves must not duplicate a mood")
        try check(data.registerMood("平静") == "平静" && data.availableMoods.count == 5, "Default moods must not be duplicated")
        try check(data.registerMood(" \n ") == nil && data.registerMood(String(repeating: "字", count: 13)) == nil, "Empty or oversized moods must not be saved")
        var entry = JournalEntry(id: "2026-11-10")
        entry.body = "记下一点事情。"
        entry.mood = "有点期待"
        data.journal[entry.id] = entry
        data.preferences = upgraded
        data.preferences.autoStartCycle = true
        data.preferences.chimeVolume = 0.8
        try file.save(data)
        let restored = try file.load()
        try check(restored.availableMoods.contains("有点期待") && restored.journal[entry.id]?.mood == "有点期待", "Custom choices and the selected journal mood must survive a restart")
        try check(restored.preferences.autoStartCycle && restored.preferences.chimeVolume == 0.8, "New timer and sound preferences must survive a restart")
        data.journal.removeAll()
        try file.save(data)
        try check(try file.load().availableMoods.contains("有点期待"), "Deleting a journal must not delete reusable mood choices")
        var oldData = try JSONSerialization.jsonObject(with: FileStore.encode(AppData())) as! [String: Any]
        oldData.removeValue(forKey: "customMoods")
        let decoded = try FileStore.decode(JSONSerialization.data(withJSONObject: oldData))
        try check(decoded.availableMoods == ["很棒", "平静", "一般", "低落"], "Existing journals must load without a custom mood field")
        return count
    }
}
