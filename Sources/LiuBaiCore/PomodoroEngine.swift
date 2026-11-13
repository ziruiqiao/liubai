import Foundation

public struct TimerCompletion: Equatable, Sendable {
    public let phase: TimerPhase
    public let finishedAt: Date
}

/// Wall-clock deadlines prevent drift. A delayed tick completes at most one phase;
/// it never invents completed rounds while the process was suspended.
public struct PomodoroEngine: Codable, Equatable, Sendable {
    public private(set) var phase: TimerPhase = .focus
    public private(set) var remaining: TimeInterval = 25 * 60
    public private(set) var deadline: Date?
    public private(set) var completedInCycle = 0
    public private(set) var phaseDuration: TimeInterval = 25 * 60
    public var isRunning: Bool { deadline != nil }
    public var hasStarted: Bool { remaining < phaseDuration || isRunning }
    public init() {}

    public func secondsRemaining(at now: Date) -> TimeInterval {
        max(0, deadline?.timeIntervalSince(now) ?? remaining)
    }
    public mutating func start(at now: Date) {
        guard deadline == nil, remaining > 0 else { return }
        deadline = now.addingTimeInterval(remaining)
    }
    public mutating func pause(at now: Date) {
        remaining = secondsRemaining(at: now)
        deadline = nil
    }
    public mutating func reset(preferences: Preferences) {
        deadline = nil
        phaseDuration = preferences.duration(for: phase)
        remaining = phaseDuration
    }
    public mutating func select(_ newPhase: TimerPhase, preferences: Preferences) {
        phase = newPhase
        reset(preferences: preferences)
    }
    public mutating func advance(to now: Date, preferences: Preferences) -> TimerCompletion? {
        guard let finish = deadline, now >= finish else { return nil }
        let completed = phase
        deadline = nil
        if completed == .focus {
            completedInCycle += 1
            if completedInCycle >= max(1, preferences.roundsBeforeLongBreak) {
                phase = .longBreak
                completedInCycle = 0
            } else { phase = .shortBreak }
        } else { phase = .focus }
        reset(preferences: preferences)
        let shouldStart: Bool
        switch completed {
        case .focus: shouldStart = preferences.autoStartBreak
        case .shortBreak: shouldStart = preferences.autoStartFocus
        case .longBreak: shouldStart = preferences.autoStartCycle
        }
        if shouldStart {
            start(at: now)
        }
        return TimerCompletion(phase: completed, finishedAt: finish)
    }
    public func pausedSnapshot(at now: Date) -> PomodoroEngine {
        var result = self
        result.pause(at: now)
        return result
    }
}

public enum Statistics {
    /// Splits intervals at local midnight. Usage is a union, not the sum of audio
    /// and focus, since those activities can happen simultaneously.
    public static func record(from start: Date, to end: Date, usage: Bool, listening: Bool, focus: Bool,
                              into days: inout [String: DailyStats], calendar: Calendar = .current) {
        guard end > start, usage || listening || focus else { return }
        var cursor = start
        while cursor < end {
            guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)), midnight > cursor else { break }
            let boundary = min(end, midnight)
            let seconds = boundary.timeIntervalSince(cursor)
            let key = DayKey.string(for: cursor, calendar: calendar)
            var item = days[key] ?? DailyStats(id: key)
            if usage { item.usageSeconds += seconds }
            if listening { item.listeningSeconds += seconds }
            if focus { item.focusSeconds += seconds; item.usedPomodoro = true }
            days[key] = item
            cursor = boundary
        }
    }
    public static func completeRound(at date: Date, into days: inout [String: DailyStats], calendar: Calendar = .current) {
        let key = DayKey.string(for: date, calendar: calendar)
        var item = days[key] ?? DailyStats(id: key)
        item.completedRounds += 1
        item.usedPomodoro = true
        days[key] = item
    }
}
