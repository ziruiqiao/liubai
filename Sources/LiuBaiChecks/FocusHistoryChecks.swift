import Foundation
import LiuBaiCore

enum FocusHistoryChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw NSError(domain: "FocusHistoryChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            count += 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 10))!
        var data = AppData()
        data.updateFocusIntention("  写完第一章\n")
        data.beginFocusBlock(at: start)
        let firstID = data.activeFocusBlockID!
        try check(data.focusBlocks?.first?.intention == "写完第一章", "Starting focus must snapshot the goal")
        for second in 0..<60 {
            data.recordFocus(from: start.addingTimeInterval(Double(second)), to: start.addingTimeInterval(Double(second + 1)))
        }
        try check(data.focusBlocks?.first?.focusSeconds == 60 && data.focusBlocks?.first?.intervals.count == 1,
                  "Per-second ticks must compact into one real-time interval")
        data.beginFocusBlock(at: start.addingTimeInterval(360))
        data.recordFocus(from: start.addingTimeInterval(360), to: start.addingTimeInterval(420))
        try check(data.activeFocusBlockID == firstID && data.focusBlocks?.count == 1,
                  "Resuming a paused round must keep its original block")
        try check(data.focusBlocks?.first?.focusSeconds == 120 && data.focusBlocks?.first?.intervals.count == 2,
                  "A five-minute pause must never count as focus")
        data.updateFocusIntention("写完第一章并校对")
        try check(data.focusBlocks?.first?.intention == data.intention,
                  "A goal entered during the current round must be saved with that round")
        data.recordFocus(from: start, to: start.addingTimeInterval(420))
        data.recordFocus(from: start.addingTimeInterval(500), to: start.addingTimeInterval(490))
        try check(data.focusBlocks?.first?.focusSeconds == 120,
                  "Overlapping callbacks and backward time changes must not double-count focus")
        data.finishFocusBlock(at: start.addingTimeInterval(420), completed: true)
        data.finishFocusBlock(at: start.addingTimeInterval(430), completed: false)
        data.updateFocusIntention("第二章")
        try check(data.focusBlocks?.first?.intention == "写完第一章并校对" && data.focusBlocks?.first?.completed == true,
                  "Finishing twice or editing a future goal must not alter a completed block")
        try check(data.activeFocusBlockID == nil && data.focusBlocks?.first?.finishedAt == start.addingTimeInterval(420),
                  "Completion must finalize at the actual timer boundary")
        let record = data.focusRecords(on: start, calendar: calendar).first!
        try check(record.startedAt == start && record.endedAt == start.addingTimeInterval(420) && record.focusSeconds == 120 && !record.isOpen,
                  "The visible time block must retain its goal, boundaries, and pause-free duration")

        data.beginFocusBlock(at: start.addingTimeInterval(600))
        data.recordFocus(from: start.addingTimeInterval(600), to: start.addingTimeInterval(615))
        data.finishFocusBlock(at: start.addingTimeInterval(615), completed: false)
        try check(data.focusBlocks?.last?.intention == "第二章" && data.focusBlocks?.last?.completed == false
                  && data.focusBlocks?.last?.focusSeconds == 15,
                  "Resetting a partial round must retain its time and goal without inventing a completed round")
        data.beginFocusBlock(at: start.addingTimeInterval(700))
        data.finishFocusBlock(at: start.addingTimeInterval(700), completed: false)
        try check(data.focusBlocks?.count == 2, "An empty reset must not create a phantom time block")

        var overnight = AppData()
        overnight.updateFocusIntention("跨日阅读")
        let midnightStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 59, second: 30))!
        overnight.recordFocus(from: midnightStart, to: midnightStart.addingTimeInterval(90))
        Statistics.record(from: midnightStart, to: midnightStart.addingTimeInterval(90), usage: true, listening: false, focus: true, into: &overnight.dailyStats, calendar: calendar)
        overnight.finishFocusBlock(at: midnightStart.addingTimeInterval(90), completed: true)
        let before = overnight.focusRecords(on: midnightStart, calendar: calendar)
        let after = overnight.focusRecords(on: midnightStart.addingTimeInterval(90), calendar: calendar)
        try check(before.count == 1 && after.count == 1 && before[0].blockID == after[0].blockID,
                  "One round spanning midnight must remain the same block on both days")
        try check(before[0].focusSeconds == 30 && after[0].focusSeconds == 60
                  && before[0].focusSeconds == overnight.dailyStats["2026-11-08"]?.focusSeconds
                  && after[0].focusSeconds == overnight.dailyStats["2026-11-09"]?.focusSeconds,
                  "Daily time blocks must agree with the existing local-midnight statistics")
        try check(before[0].intention == "跨日阅读" && after[0].intention == before[0].intention,
                  "The goal must survive a midnight boundary")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dst = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let dstEnd = calendar.date(byAdding: .day, value: 1, to: dst)!
        var daylight = AppData()
        daylight.recordFocus(from: dst, to: dstEnd)
        try check(daylight.focusRecords(on: dst, calendar: calendar).first?.focusSeconds == 23 * 3600,
                  "Time-block day boundaries must respect daylight saving time")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("liubai-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileStore(directory: directory)
        var open = data
        open.beginFocusBlock(at: start.addingTimeInterval(900))
        open.recordFocus(from: start.addingTimeInterval(900), to: start.addingTimeInterval(930))
        var note = JournalEntry(id: "2026-11-08"); note.body = "原有手记"
        open.journal[note.id] = note
        try store.save(open)
        var restored = try store.load()
        try check(restored.focusBlocks == open.focusBlocks && restored.activeFocusBlockID == open.activeFocusBlockID
                  && restored.journal == open.journal, "Disk saves and exports must preserve history, the paused round, and existing diary entries")
        restored.beginFocusBlock(at: start.addingTimeInterval(1200))
        restored.recordFocus(from: start.addingTimeInterval(1200), to: start.addingTimeInterval(1230))
        try check(restored.focusBlocks?.count == 3 && restored.focusBlocks?.last?.focusSeconds == 60,
                  "Continuing after relaunch must reuse the unfinished block without counting time away")

        var legacy = try JSONSerialization.jsonObject(with: FileStore.encode(open)) as! [String: Any]
        legacy.removeValue(forKey: "focusBlocks"); legacy.removeValue(forKey: "activeFocusBlockID")
        let old = try FileStore.decode(JSONSerialization.data(withJSONObject: legacy))
        try check(old.focusBlocks == nil && old.activeFocusBlockID == nil && old.journal == open.journal,
                  "Older data must remain readable without inventing historical goals or replacing diary entries")
        return count
    }
}
