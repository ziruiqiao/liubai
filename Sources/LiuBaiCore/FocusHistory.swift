import Foundation

public struct FocusInterval: Codable, Equatable, Sendable {
    public let start: Date
    public fileprivate(set) var end: Date
    public var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// One timer round, with separate intervals so pauses never count as focus.
public struct FocusBlock: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public fileprivate(set) var intention: String
    public fileprivate(set) var intervals: [FocusInterval] = []
    public fileprivate(set) var finishedAt: Date?
    public fileprivate(set) var completed = false
    public var focusSeconds: TimeInterval { intervals.reduce(0) { $0 + $1.seconds } }

    fileprivate init(intention: String, startedAt: Date) {
        id = UUID(); self.intention = intention; self.startedAt = startedAt
    }

    fileprivate mutating func record(from start: Date, to end: Date) {
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite else { return }
        let start = max(startedAt, max(start, intervals.last?.end ?? start))
        guard end > start, finishedAt == nil else { return }
        if let last = intervals.last, abs(last.end.timeIntervalSince(start)) < 0.001 {
            intervals[intervals.count - 1].end = end
        } else { intervals.append(FocusInterval(start: start, end: end)) }
    }
}

public struct FocusBlockDay: Identifiable, Equatable, Sendable {
    public var id: String { "\(blockID.uuidString)-\(day)" }
    public let blockID: UUID
    public let day: String
    public let intention: String
    public let startedAt: Date
    public let endedAt: Date
    public let focusSeconds: TimeInterval
    public let completed: Bool
    public let isOpen: Bool
}

public extension AppData {
    private var activeFocusIndex: Int? {
        guard let id = activeFocusBlockID else { return nil }
        return focusBlocks?.firstIndex { $0.id == id && $0.finishedAt == nil }
    }

    mutating func beginFocusBlock(at date: Date) {
        guard activeFocusIndex == nil else { return }
        let block = FocusBlock(intention: intention.trimmingCharacters(in: .whitespacesAndNewlines), startedAt: date)
        if focusBlocks == nil { focusBlocks = [] }
        focusBlocks?.append(block)
        activeFocusBlockID = block.id
    }

    mutating func updateFocusIntention(_ value: String) {
        intention = value
        if let index = activeFocusIndex {
            focusBlocks?[index].intention = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    mutating func recordFocus(from start: Date, to end: Date) {
        guard end > start else { return }
        beginFocusBlock(at: start)
        guard let index = activeFocusIndex else { return }
        focusBlocks?[index].record(from: start, to: end)
    }

    mutating func finishFocusBlock(at date: Date, completed: Bool) {
        guard let index = activeFocusIndex else { activeFocusBlockID = nil; return }
        var block = focusBlocks![index]
        if block.focusSeconds > 0 {
            block.finishedAt = max(date, block.intervals.last!.end)
            block.completed = completed
            focusBlocks?[index] = block
        } else { focusBlocks?.remove(at: index) }
        activeFocusBlockID = nil
    }

    /// Only display the part actually recorded on the selected local day.
    func focusRecords(on date: Date, calendar: Calendar = .current) -> [FocusBlockDay] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let key = DayKey.string(for: date, calendar: calendar)
        return (focusBlocks ?? []).compactMap { block in
            let intervals = block.intervals.compactMap { interval -> (Date, Date)? in
                let left = max(start, interval.start), right = min(end, interval.end)
                return right > left ? (left, right) : nil
            }
            let isOpen = block.id == activeFocusBlockID && block.finishedAt == nil
            if intervals.isEmpty {
                guard isOpen, block.startedAt >= start, block.startedAt < end else { return nil }
            }
            return FocusBlockDay(blockID: block.id, day: key, intention: block.intention,
                                 startedAt: intervals.first?.0 ?? block.startedAt,
                                 endedAt: intervals.last?.1 ?? block.startedAt,
                                 focusSeconds: intervals.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) },
                                 completed: block.completed, isOpen: isOpen)
        }.sorted { $0.startedAt > $1.startedAt }
    }
}
