import AppKit
import LiuBaiCore
import SwiftUI
import Observation

// Interface colours and the generated app icon share Resources/Theme.json.
// Sky artwork deliberately lives in SkyPalette.swift.
struct ThemeOption: Decodable, Identifiable {
    let id: String
    let name: String
    let colors: [String: String]
}

private struct ThemeConfiguration: Decodable {
    let colors: [String: String]
    let opacity: [String: Double]
    let defaultTheme: String?
    let themes: [ThemeOption]?
    static let base: ThemeConfiguration = {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Theme.json")
        var url = Bundle.main.url(forResource: "Theme", withExtension: "json") ?? source
        #if DEBUG
        if CommandLine.arguments.contains("--render-focus-previews"), let path = ProcessInfo.processInfo.environment["LIUBAI_PREVIEW_THEME"] {
            url = URL(fileURLWithPath: path)
        }
        #endif
        do { return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
        catch { fatalError("Cannot load Theme.json: \(error)") }
    }()
    static var current: ThemeConfiguration {
        let base = Self.base
        let overrides = base.themes?.first { $0.id == ThemeManager.shared.selectedID }?.colors ?? [:]
        return ThemeConfiguration(colors: base.colors.merging(overrides) { _, new in new }, opacity: base.opacity, defaultTheme: nil, themes: nil)
    }
    func color(_ key: String) -> Color {
        guard let value = colors[key] else { preconditionFailure("Missing theme colour: \(key)") }
        if value == "systemLabel" { return Color(nsColor: .labelColor) }
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { preconditionFailure("Invalid theme colour: \(key)") }
        return Color(hex: number)
    }
    func alpha(_ key: String) -> Double {
        guard let value = opacity[key], value.isFinite, (0...1).contains(value) else { preconditionFailure("Invalid theme opacity: \(key)") }
        return value
    }
}

// Observation tracks palette reads inside every SwiftUI body, including sheets
// and controls, without recreating views or interrupting native text composition.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()
    private(set) var selectedID: String
    var options: [ThemeOption] { ThemeConfiguration.base.themes ?? [] }
    private var isPreview: Bool { CommandLine.arguments.contains("--render-focus-previews") }
    private init() {
        let base = ThemeConfiguration.base
        let saved = CommandLine.arguments.contains("--render-focus-previews") ? nil : UserDefaults.standard.string(forKey: "liubai.theme")
        selectedID = base.themes?.contains(where: { $0.id == saved }) == true ? saved! : (base.defaultTheme ?? "indigo")
    }
    func select(_ id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        let animation: Animation? = isPreview || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.28)
        withAnimation(animation) { selectedID = id }
        if !isPreview { UserDefaults.standard.set(id, forKey: "liubai.theme") }
    }
    func updateDockIcon() {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }
}

enum Palette {
    static var background: Color { ThemeConfiguration.current.color("background") }
    static var sidebar: Color { ThemeConfiguration.current.color("sidebar") }
    static var surface: Color { ThemeConfiguration.current.color("surface") }
    static var text: Color { ThemeConfiguration.current.color("text") }
    static var secondary: Color { ThemeConfiguration.current.color("secondary") }
    static var line: Color { ThemeConfiguration.current.color("line") }
    static var accent: Color { ThemeConfiguration.current.color("accent") }
    static var softAccent: Color { ThemeConfiguration.current.color("softAccent") }
    static var warm: Color { ThemeConfiguration.current.color("warm") }
    static var softWarm: Color { ThemeConfiguration.current.color("softWarm") }
    static var onAccent: Color { ThemeConfiguration.current.color("onAccent") }
    static var outline: Color { ThemeConfiguration.current.color("outline") }
    static var shadow: Color { ThemeConfiguration.current.color("shadow") }
    static var qrBackground: Color { ThemeConfiguration.current.color("qrBackground") }
    static var restAccent: Color { ThemeConfiguration.current.color("restAccent") }
    static var logoTop: Color { ThemeConfiguration.current.color("logoTop") }
    static var logoBottom: Color { ThemeConfiguration.current.color("logoBottom") }
    static var logoGlyph: Color { ThemeConfiguration.current.color("logoGlyph") }
    static var menuBarIcon: Color { ThemeConfiguration.current.color("menuBarIcon") }
    static var menuBarText: Color { ThemeConfiguration.current.color("menuBarText") }
}

enum ThemeOpacity {
    static var cardOnSky: Double { ThemeConfiguration.current.alpha("cardOnSky") }
    static var timerCard: Double { ThemeConfiguration.current.alpha("timerCard") }
    static var floatingPlayer: Double { ThemeConfiguration.current.alpha("floatingPlayer") }
    static var floatingPlayerBorder: Double { ThemeConfiguration.current.alpha("floatingPlayerBorder") }
    static var menuChip: Double { ThemeConfiguration.current.alpha("menuChip") }
    static var menuTimer: Double { ThemeConfiguration.current.alpha("menuTimer") }
    static var menuMusic: Double { ThemeConfiguration.current.alpha("menuMusic") }
    static var menuAction: Double { ThemeConfiguration.current.alpha("menuAction") }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct TimerColors {
    let ink = Palette.text
    let secondary = ThemeConfiguration.current.color("timerSecondary")
    let accent = Palette.accent
    let face = ThemeConfiguration.current.color("timerFace")
    let controls = ThemeConfiguration.current.color("timerControls")
    let track = ThemeConfiguration.current.color("timerTrack")
}

struct OverlayColors {
    let ink: Color
    let secondary: Color
    let accent: Color
    let track: Color
    init(_ sky: FocusSky) {
        let mode = sky.daylight >= 0.5 ? "Day" : "Night"
        ink = ThemeConfiguration.current.color("overlayText" + mode)
        secondary = ThemeConfiguration.current.color("overlaySecondary" + mode)
        track = ThemeConfiguration.current.color("overlayTrack" + mode)
        let a = NSColor(ThemeConfiguration.current.color("overlayAccentNight")).usingColorSpace(.sRGB)!
        let b = NSColor(ThemeConfiguration.current.color("overlayAccentDay")).usingColorSpace(.sRGB)!
        let t = sky.daylight
        accent = Color(.sRGB, red: a.redComponent * (1-t) + b.redComponent * t, green: a.greenComponent * (1-t) + b.greenComponent * t, blue: a.blueComponent * (1-t) + b.blueComponent * t, opacity: 1)
    }
}
