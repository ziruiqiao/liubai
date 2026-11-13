import AppKit
import Combine
import Foundation
import LiuBaiAudio
import LiuBaiCore
import UniformTypeIdentifiers

enum Screen: String, CaseIterable {
    case focus, library, statistics, journal, settings
    var title: String {
        switch self { case .focus: return "专注空间"; case .library: return "我的音乐"; case .statistics: return "时光统计"; case .journal: return "每日手记"; case .settings: return "偏好设置" }
    }
    var icon: String {
        switch self { case .focus: return "circle.dotted.circle"; case .library: return "music.note.list"; case .statistics: return "chart.bar.xaxis"; case .journal: return "book.closed"; case .settings: return "slider.horizontal.3" }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var data = AppData()
    @Published var screen: Screen = .focus
    @Published var showImport = false
    @Published var showCollectionImport = false
    @Published private(set) var playbackKeys: [String]?
    private var playbackCollectionID: String?
    @Published var notice: String?
    @Published var storageError: String?
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var savePending = false
    @Published private(set) var now = Date()
    let client = BilibiliClient()
    let favorites = FavoritesController()
    let weather = WeatherController()
    let audio: AudioController
    let fileStore: FileStore
    private var clock: AnyCancellable?
    private var saveTask: Task<Void, Never>?
    private var lastTick = Date()
    private var lastDiskSave = Date()
    private var canPersist = true
    private var observers: [NSObjectProtocol] = []
    private var resumeMusicAfterBreak = false
    private var sleeping = false
    private let completionChime = CompletionChime()

    init() {
        fileStore = FileStore(legacyDirectory: Self.previousDataDirectory())
        audio = AudioController(client: client)
        do {
            let isFirstLaunch = !FileManager.default.fileExists(atPath: fileStore.fileURL.path)
            data = try fileStore.load()
            if isFirstLaunch, !FileManager.default.fileExists(atPath: fileStore.fileURL.path),
               let starterURL = Bundle.main.url(forResource: "StarterTracks", withExtension: "json") {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                for track in try decoder.decode([Track].self, from: Data(contentsOf: starterURL)) { data.addToMyMusic(track) }
            }
            data.timer = data.timer.pausedSnapshot(at: Date())
            if !data.timer.hasStarted { data.timer.reset(preferences: data.preferences) }
        } catch {
            storageError = "本地数据未能读取，原文件已保留。\(error.localizedDescription)"
            canPersist = false
        }
        audio.setVolume(data.preferences.volume)
        audio.onEnded = { [weak self] in self?.nextTrack() }
        audio.onActivityChange = { [weak self] in self?.recordActivity() }
        clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            Task { @MainActor in self?.tick(at: date) }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspendForSleep() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.saveNow() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.weather.requestLocation(allowPrompt: false)
                self?.weather.refresh(force: false)
            }
        })
    }

    private static func previousDataDirectory() -> URL? {
        guard ProcessInfo.processInfo.environment["LIUBAI_DATA_DIR"] == nil else { return nil }
        // The first local prototype was used directly from this project. When
        // the release App is first opened here, retain that user's latest data.
        // Independent preview subdirectories are intentionally not candidates.
        var candidate = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<4 {
            let manifest = candidate.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8), text.contains("name: \"LiuBai\"") {
                let previous = candidate.appendingPathComponent(".local-data", isDirectory: true)
                if FileManager.default.fileExists(atPath: previous.appendingPathComponent("liubai.json").path) { return previous }
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    var today: DailyStats { stats(for: now) }
    var remaining: TimeInterval { data.timer.secondsRemaining(at: now) }
    var timerProgress: Double { max(0, min(1, 1 - remaining / max(1, data.timer.phaseDuration))) }
    var savedDescription: String {
        if storageError != nil { return "保存遇到问题" }
        if savePending { return "正在保存…" }
        return lastSavedAt == nil ? "只保存在这台 Mac" : "已保存到这台 Mac"
    }
    func stats(for date: Date) -> DailyStats {
        let key = DayKey.string(for: date)
        return data.dailyStats[key] ?? DailyStats(id: key)
    }

    func toggleTimer() {
        tick(at: Date())
        if data.timer.isRunning { data.timer.pause(at: now) }
        else {
            if data.timer.remaining <= 0 { data.timer.reset(preferences: data.preferences) }
            data.timer.start(at: now)
            if data.timer.phase == .focus {
                data.beginFocusBlock(at: now)
                let key = DayKey.string(for: now)
                var day = data.dailyStats[key] ?? DailyStats(id: key)
                day.usedPomodoro = true
                data.dailyStats[key] = day
                resumeBreakMusicIfFocusing()
            }
        }
        saveNow()
    }
    func resetTimer() {
        tick(at: Date())
        data.finishFocusBlock(at: now, completed: false)
        data.timer.reset(preferences: data.preferences)
        saveNow()
    }
    func selectPhase(_ phase: TimerPhase) {
        tick(at: Date())
        data.finishFocusBlock(at: now, completed: false)
        data.timer.select(phase, preferences: data.preferences)
        if phase != .focus && data.preferences.pauseMusicDuringBreak { pauseForBreak() }
        saveNow()
    }
    func updatePreferences(_ update: (inout Preferences) -> Void) {
        update(&data.preferences)
        audio.setVolume(data.preferences.volume)
        if !data.timer.hasStarted { data.timer.reset(preferences: data.preferences) }
        scheduleSave()
    }
    func updateIntention(_ value: String) { data.updateFocusIntention(value); scheduleSave() }
    func setWeatherEnabled(_ enabled: Bool) {
        data.weatherEnabled = enabled
        weather.start(enabled: enabled)
        scheduleSave()
    }

    func importTrack(_ input: String) async throws {
        let track = try await client.resolve(input)
        guard data.addToMyMusic(track) else {
            notice = "这首音乐已经在列表里了。"
            return
        }
        saveNow()
        notice = "已添加到我的音乐。"
    }
    var myMusic: [Track] { data.myMusic }
    var collections: [LibraryCollection] { data.collections ?? [] }
    @discardableResult
    func importCollection(_ preview: LibraryPreview, selected: Set<String>) -> (added: Int, duplicates: Int) {
        let result = data.addCollection(preview, selected: selected)
        saveNow()
        notice = "已向合集加入 \(result.added) 段声音\(result.duplicates > 0 ? "，\(result.duplicates) 段已存在" : "")。"
        return result
    }
    func play(_ track: Track, in queue: [Track]? = nil, collectionID: String? = nil) {
        recordActivity()
        playbackCollectionID = collectionID
        playbackKeys = queue?.map(\.libraryKey)
        if audio.currentTrack?.libraryKey == track.libraryKey { audio.toggle() }
        else { audio.load(track) }
    }
    var playbackTracks: [Track] {
        guard let playbackKeys else { return myMusic }
        return data.tracks(for: playbackKeys)
    }
    func tracks(in collection: LibraryCollection) -> [Track] {
        data.tracks(in: collection)
    }
    func playCollection(_ collection: LibraryCollection) {
        let queue = tracks(in: collection)
        guard let first = queue.first else { return }
        playbackCollectionID = collection.id
        playbackKeys = queue.map(\.libraryKey)
        audio.load(first)
    }
    func removeCollection(_ collection: LibraryCollection) {
        data.removeCollection(id: collection.id)
        reconcilePlaybackQueue()
        saveNow()
    }
    func togglePlayback() {
        if audio.currentTrack != nil { audio.toggle() }
        else if let first = playbackTracks.first { audio.load(first) }
        else { showImport = true }
    }
    func nextTrack() {
        let queue = playbackTracks
        guard !queue.isEmpty else { return }
        if data.preferences.repeatTrack, let current = audio.currentTrack { audio.load(current); return }
        let index = queue.firstIndex(where: { $0.libraryKey == audio.currentTrack?.libraryKey }) ?? -1
        audio.load(queue[(index + 1) % queue.count])
    }
    func previousTrack() {
        let queue = playbackTracks
        guard !queue.isEmpty else { return }
        if audio.position > 3 { audio.seek(to: 0); return }
        let index = queue.firstIndex(where: { $0.libraryKey == audio.currentTrack?.libraryKey }) ?? 0
        audio.load(queue[(index - 1 + queue.count) % queue.count])
    }
    func removeTrack(_ track: Track, from collectionID: String? = nil) {
        data.removeMusic(key: track.libraryKey, from: collectionID)
        reconcilePlaybackQueue()
        saveNow()
    }
    func moveTrack(_ track: Track, by delta: Int, in collectionID: String? = nil) {
        data.moveMusic(key: track.libraryKey, by: delta, in: collectionID)
        saveNow()
    }

    private func reconcilePlaybackQueue() {
        let allowed: [Track]
        if let id = playbackCollectionID {
            allowed = collections.first(where: { $0.id == id }).map { tracks(in: $0) } ?? []
        } else { allowed = myMusic }
        let keys = Set(allowed.map(\.libraryKey))
        if let playbackKeys { self.playbackKeys = playbackKeys.filter { keys.contains($0) } }
        if let current = audio.currentTrack, !keys.contains(current.libraryKey) { audio.stop() }
        if playbackCollectionID != nil && allowed.isEmpty {
            playbackCollectionID = nil
            playbackKeys = nil
        }
    }

    func entry(for date: Date) -> JournalEntry {
        let key = DayKey.string(for: date)
        return data.journal[key] ?? JournalEntry(id: key)
    }
    func updateJournal(for date: Date, _ update: (inout JournalEntry) -> Void) {
        var entry = entry(for: date)
        update(&entry)
        entry.updatedAt = Date()
        data.journal[entry.id] = entry
        scheduleSave()
    }
    func addMood(_ input: String, for date: Date) -> Bool {
        guard let mood = data.registerMood(input) else { return false }
        updateJournal(for: date) { $0.mood = mood }
        saveNow()
        return true
    }
    func previewCompletionSound() { completionChime.play(volume: data.preferences.chimeVolume) }
    func deleteJournal(for date: Date) {
        data.journal.removeValue(forKey: DayKey.string(for: date))
        saveNow()
    }
    func exportData() {
        saveNow()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "留白备份-\(DayKey.string(for: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var snapshot = data
            snapshot.timer = data.timer.pausedSnapshot(at: Date())
            try FileStore.encode(snapshot).write(to: url, options: .atomic)
            notice = "数据已导出。"
        } catch { notice = "导出失败：\(error.localizedDescription)" }
    }
    func exportJournal(for date: Date) {
        let entry = entry(for: date)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "留白手记-\(entry.id).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = "# \(entry.title.isEmpty ? entry.id : entry.title)\n\n日期：\(entry.id) · 心情：\(entry.mood)\n\n\(entry.body)\n"
        do { try content.write(to: url, atomically: true, encoding: .utf8); notice = "手记已导出。" }
        catch { notice = "导出失败：\(error.localizedDescription)" }
    }
    func showDataInFinder() { NSWorkspace.shared.activateFileViewerSelecting([fileStore.fileURL]) }
    func retryStorage() {
        do {
            if !canPersist { data = try fileStore.load(); data.timer = data.timer.pausedSnapshot(at: Date()) }
            canPersist = true
            saveNow()
        } catch { storageError = "本地数据仍无法读取，原文件已保留。\(error.localizedDescription)" }
    }

    func shutdown() {
        weather.stop()
        tick(at: Date())
        data.timer.pause(at: now)
        audio.pause()
        saveTask?.cancel()
        saveNow()
    }
    func saveNow() {
        saveTask?.cancel()
        guard canPersist else { return }
        do {
            var snapshot = data
            snapshot.timer = data.timer.pausedSnapshot(at: Date())
            try fileStore.save(snapshot)
            lastSavedAt = Date(); lastDiskSave = Date(); storageError = nil; savePending = false
        } catch { storageError = "保存失败，内容暂留在内存中。\(error.localizedDescription)" }
    }
    private func scheduleSave() {
        saveTask?.cancel()
        savePending = true
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
    private func recordActivity(at date: Date = Date()) {
        let start = lastTick
        lastTick = date; now = date
        guard !sleeping, date > start else { return }
        // A very late callback can follow suspension without a sleep notification.
        // Cap such intervals rather than claiming hours of unobserved activity.
        let safeStart = max(start, date.addingTimeInterval(-10))
        let running = data.timer.isRunning
        let focusEnd = min(date, data.timer.deadline ?? date)
        let isFocus = running && data.timer.phase == .focus
        let foreground = NSApp.isActive && NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
        let active = foreground || audio.isPlaying || running
        if focusEnd > safeStart {
            Statistics.record(from: safeStart, to: focusEnd, usage: active, listening: audio.isPlaying,
                              focus: isFocus, into: &data.dailyStats)
            if isFocus { data.recordFocus(from: safeStart, to: focusEnd) }
        }
        if focusEnd < date {
            Statistics.record(from: max(safeStart, focusEnd), to: date, usage: foreground || audio.isPlaying,
                              listening: audio.isPlaying, focus: false, into: &data.dailyStats)
        }
    }
    private func tick(at date: Date) {
        recordActivity(at: date)
        if let completion = data.timer.advance(to: date, preferences: data.preferences) {
            if completion.phase == .focus {
                data.finishFocusBlock(at: completion.finishedAt, completed: true)
                Statistics.completeRound(at: completion.finishedAt, into: &data.dailyStats)
                if data.preferences.pauseMusicDuringBreak { pauseForBreak() }
                notice = "本轮专注已完成。"
            } else {
                notice = "休息已结束。"
            }
            if data.timer.isRunning && data.timer.phase == .focus { data.beginFocusBlock(at: date) }
            resumeBreakMusicIfFocusing()
            if data.preferences.soundEnabled { completionChime.play(volume: data.preferences.chimeVolume) }
            saveNow()
        } else if date.timeIntervalSince(lastDiskSave) >= 15 { saveNow() }
    }
    private func resumeBreakMusicIfFocusing() {
        // Preparing a focus phase after a break is not the same as starting it.
        guard data.timer.phase == .focus, data.timer.isRunning, resumeMusicAfterBreak else { return }
        resumeMusicAfterBreak = false
        audio.resume()
    }
    private func pauseForBreak() {
        if audio.wantsToPlay { resumeMusicAfterBreak = true; audio.pause() }
    }
    private func suspendForSleep() {
        tick(at: Date())
        data.timer.pause(at: now)
        audio.pause()
        sleeping = true
        saveNow()
        notice = "Mac 休眠时，计时和音乐已暂停。"
    }
    private func wake() {
        sleeping = false; lastTick = Date(); now = lastTick
        weather.requestLocation(allowPrompt: false)
        weather.refresh(force: false)
    }
}

#if DEBUG
extension AppStore {
    /// Exercise the actual completion/manual-start paths without network audio.
    func checkBreakMusicResumption() throws {
        let original = data
        let originalPending = resumeMusicAfterBreak
        let originalTick = lastTick
        let originalNow = now
        defer {
            data = original
            resumeMusicAfterBreak = originalPending
            lastTick = originalTick
            now = originalNow
            saveNow()
        }
        for phase in [TimerPhase.shortBreak, .longBreak] {
            for automatically in [false, true] {
                data = AppData()
                data.preferences.soundEnabled = false
                data.preferences.autoStartFocus = phase == .shortBreak ? automatically : !automatically
                data.preferences.autoStartCycle = phase == .longBreak ? automatically : !automatically
                data.timer.select(phase, preferences: data.preferences)
                let finish = Date()
                data.timer.start(at: finish.addingTimeInterval(-data.preferences.duration(for: phase)))
                resumeMusicAfterBreak = true
                tick(at: finish)
                guard data.timer.isRunning == automatically, resumeMusicAfterBreak == !automatically else {
                    throw NSError(domain: "BreakMusicCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "休息结束等待期间，必须保留暂停音乐，直到专注真正开始。"])
                }
                if !automatically {
                    selectPhase(.focus)
                    guard resumeMusicAfterBreak else {
                        throw NSError(domain: "BreakMusicCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "只选择专注阶段不能自动恢复音乐。"])
                    }
                    toggleTimer()
                    guard data.timer.isRunning, !resumeMusicAfterBreak else {
                        throw NSError(domain: "BreakMusicCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "手动开始专注时应恢复此前因休息暂停的音乐。"])
                    }
                }
            }
        }
    }
}
#endif
