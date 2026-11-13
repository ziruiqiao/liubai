#if DEBUG
import AppKit
import LiuBaiCore
import SwiftUI

/// Render the real timer card at several local hours, without changing macOS's
/// clock, time zone, user settings, or the currently running App.
@MainActor
enum SkyPreviewExporter {
    static func renderFocus(to directory: String) throws {
        let environment = ProcessInfo.processInfo.environment
        let production = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LiuBai").resolvingSymlinksInPath().path
        let legacy = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".local-data").resolvingSymlinksInPath().path
        guard let dataPath = environment["LIUBAI_DATA_DIR"], !dataPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              URL(fileURLWithPath: dataPath).resolvingSymlinksInPath().path != production,
              URL(fileURLWithPath: dataPath).resolvingSymlinksInPath().path != legacy else {
            throw NSError(domain: "SkyPreview", code: 4, userInfo: [NSLocalizedDescriptionKey: "预览需通过 LIUBAI_DATA_DIR 指定独立的数据副本。"])
        }
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let store = AppStore()
        try NativeChecks.run(store: store)
        if CommandLine.arguments.contains("--native-checks-only") { return }
        let initialTheme = ThemeManager.shared.selectedID
        for option in ThemeManager.shared.options {
            ThemeManager.shared.select(option.id)
            let date = Calendar.autoupdatingCurrent.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
            let view = RootView(skyDate: date, motionDate: date).environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather)
            try snapshot(view, width: 1200, height: 840).write(to: destination.appendingPathComponent("theme-\(option.id).png"))
            try snapshot(MenuBarView(skyDate: date, motionDate: date).environmentObject(store).environmentObject(store.audio).environmentObject(store.weather), width: 320, height: 350, chrome: false).write(to: destination.appendingPathComponent("menu-theme-\(option.id).png"))
        }
        ThemeManager.shared.select(initialTheme)
        store.screen = .focus
        store.data.preferences = Preferences()
        store.data.timer.select(.focus, preferences: store.data.preferences)
        store.data.intention = ""
        let start = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        let skyReferenceDate = start.addingTimeInterval(9 * 3600)
        try snapshot(FocusSkyScene(date: skyReferenceDate, motionDate: skyReferenceDate), width: 1000, height: 600, chrome: false)
            .write(to: destination.appendingPathComponent("sky-reference.png"))
        for (hour, width, height) in [(9.0, 1200.0, 840.0), (17.5, 1200, 840), (21.0, 1200, 840), (9.0, 1600, 1000), (21.0, 1600, 1000)] {
            let date = start.addingTimeInterval(hour * 3600)
            let view = RootView(skyDate: date, motionDate: date)
                .environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather)
            let png = try snapshot(view, width: width, height: height)
            try png.write(to: destination.appendingPathComponent(String(format: "focus-%04.1f-%d.png", hour, Int(width))))
        }
        for page in [Screen.library, .statistics, .journal, .settings] {
            store.screen = page
            // Replace any existing entries with explicit demonstration text.
            if page == .journal {
                var demo = JournalEntry(id: DayKey.string(for: Date()))
                demo.title = "让事情一点点完成"
                demo.body = "今天把想做的事情拆成了两段。\n\n09:00  阅读并整理笔记。\n10:00  写第一章的提纲。\n\n听着熟悉的音乐，把眼前的一件事做好。剩下的，明天再说。"
                store.data.journal = [demo.id: demo]
            }
            let png = try snapshot(RootView().environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather), width: 1200, height: 840)
            try png.write(to: destination.appendingPathComponent("\(page.rawValue).png"))
        }
        store.screen = .focus
        for (name, hour, width, height) in [("minimum", 9.0, 1080.0, 760.0), ("night", 21.0, 1200, 840), ("large", 9.0, 1600, 1000)] {
            let date = start.addingTimeInterval(hour * 3600)
            let view = RootView(skyDate: date, motionDate: date, sidebarCollapsedOverride: true)
                .environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather)
            try snapshot(view, width: width, height: height).write(to: destination.appendingPathComponent("focus-collapsed-\(name).png"))
        }
        for (name, effect, hour, width, height) in [
            ("minimum", SkyWeather.clear, 9.0, 1080.0, 760.0),
            ("rain", .rainPreview, 9.0, 1200, 840),
            ("cloudy", .cloudyPreview, 9.0, 1200, 840),
            ("heavy-rain", .heavyRainPreview, 9.0, 1200, 840),
            ("heavy-snow", .heavySnowPreview, 9.0, 1200, 840),
            ("snow", .snowPreview, 9.0, 1200, 840),
            ("wind", .windPreview, 9.0, 1200, 840),
            ("rain-night", .rainPreview, 21.0, 1200, 840)
        ] {
            let date = start.addingTimeInterval(hour * 3600)
            let view = RootView(skyDate: date, motionDate: date, weatherOverride: effect)
                .environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather)
            try snapshot(view, width: width, height: height).write(to: destination.appendingPathComponent("focus-\(name).png"))
        }
        for (name, hour, mode, card) in [
            ("day", 9.0, "晴", false),
            ("rain", 9.0, "雨", false),
            ("night", 21.0, "雪", false),
            ("cloudy", 9.0, "多云", false),
            ("heavy-rain", 9.0, "暴雨", false),
            ("heavy-snow", 9.0, "暴雪", false),
            ("with-card", 9.0, "晴", true)
        ] {
            let view = SkyPreviewView(hour: hour, weatherMode: mode, showsTimerCard: card)
                .environmentObject(store).environmentObject(store.weather)
            try snapshot(view, width: 700, height: 650).write(to: destination.appendingPathComponent("sky-preview-\(name).png"))
        }
        for (name, hour) in [("day", 9.0), ("night", 21.0)] {
            let date = start.addingTimeInterval(hour * 3600)
            let view = MenuBarView(skyDate: date, motionDate: date)
                .environmentObject(store).environmentObject(store.audio).environmentObject(store.weather)
            try snapshot(view, width: 320, height: 350, chrome: false).write(to: destination.appendingPathComponent("menu-bar-\(name).png"))
        }
        store.setWeatherEnabled(false)
        store.screen = .focus
        try snapshot(RootView(skyDate: start.addingTimeInterval(9 * 3600), motionDate: start)
            .environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather), width: 1080, height: 760)
            .write(to: destination.appendingPathComponent("weather-off.png"))
        var example = AppData()
        example.updateFocusIntention("阅读并整理今天的笔记")
        let sessionStart = start.addingTimeInterval(9 * 3600)
        example.recordFocus(from: sessionStart, to: sessionStart.addingTimeInterval(25 * 60))
        example.finishFocusBlock(at: sessionStart.addingTimeInterval(25 * 60), completed: true)
        example.updateFocusIntention("写完第一章的提纲，再整理下一步的问题")
        example.recordFocus(from: sessionStart.addingTimeInterval(3600), to: sessionStart.addingTimeInterval(3600 + 12 * 60))
        example.finishFocusBlock(at: sessionStart.addingTimeInterval(3600 + 12 * 60), completed: false)
        store.data.focusBlocks = example.focusBlocks
        store.screen = .statistics
        try snapshot(RootView().environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather), width: 1200, height: 840)
            .write(to: destination.appendingPathComponent("focus-records.png"))
    }

    private static func snapshot<V: View>(_ view: V, width: Double, height: Double, chrome: Bool = true) throws -> Data {
        let hosting = NSHostingView(rootView: view)
        let mask: NSWindow.StyleMask = chrome ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: height), styleMask: mask, backing: .buffered, defer: false)
        if chrome { WindowChromeView.configure(window) }
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrame(NSRect(x: -20000, y: -20000, width: width, height: height), display: false)
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let frameView = window.contentView?.superview ?? hosting
        let capture = frameView.bounds
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: capture) else {
            throw NSError(domain: "SkyPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "专注空间预览渲染失败"])
        }
        frameView.cacheDisplay(in: capture, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SkyPreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "预览图片编码失败"])
        }
        return png
    }

    static func render(to directory: String) throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let store = AppStore()
        store.data.preferences = Preferences()
        store.data.timer.select(.focus, preferences: store.data.preferences)
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: Date())
        for hour in [0.0, 6.25, 9, 12, 15, 17.5, 21] {
            let date = start.addingTimeInterval(hour * 3600)
            let view = TimerPanel(skyDate: date, motionDate: date, offersSkyPreview: false).environmentObject(store)
                .frame(width: 570).padding(18).background(Palette.background).preferredColorScheme(.light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "SkyPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "天空预览渲染失败"])
            }
            try png.write(to: destination.appendingPathComponent(String(format: "sky-%04.1f.png", hour)))
        }
    }
}
#endif
