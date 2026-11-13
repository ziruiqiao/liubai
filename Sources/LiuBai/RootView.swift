import AppKit
import LiuBaiCore
import SwiftUI

struct RootView: View {
    var skyDate: Date? = nil
    var motionDate: Date? = nil
    var weatherOverride: SkyWeather? = nil
    var sidebarCollapsedOverride: Bool? = nil
    @AppStorage("liubai.sidebarCollapsed") private var sidebarCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isSidebarCollapsed: Bool { sidebarCollapsedOverride ?? sidebarCollapsed }
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var weather: WeatherController
    var body: some View {
        HStack(spacing: 0) {
            if !isSidebarCollapsed { sidebar }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let error = store.storageError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error).font(.system(size: 12)).lineLimit(3)
                            Spacer()
                            Button("查看文件") { store.showDataInFinder() }
                            Button("重试") { store.retryStorage() }
                        }.foregroundStyle(Palette.warm).padding(12).background(Palette.softWarm, in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 16)
                    }
                    content
                }.padding(.horizontal, 30).padding(.top, 25).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if store.screen == .focus {
                    PlayerBar(floating: true)
                        .frame(maxWidth: 940)
                        .padding(.horizontal, 24).padding(.bottom, 16)
                } else { PlayerBar() }
            }
            .background {
                if store.screen == .focus {
                    FocusSkyBackground(dateOverride: skyDate, motionOverride: motionDate, weather: weatherOverride ?? weather.visuals)
                        .clipped()
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
            .environment(\.focusSkySurface, store.screen == .focus)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isSidebarCollapsed)
        .background(Palette.background).foregroundStyle(Palette.text).tint(Palette.accent)
        .preferredColorScheme(.light)
        .frame(minWidth: 1080, minHeight: 760)
        .background(WindowChromeView().allowsHitTesting(false))
        .overlay {
            if store.screen == .focus {
                // Measure the whole window, including the sidebar, title bar
                // and player, rather than the remaining focus content area.
                GeometryReader { geometry in
                    TimerDial(skyDate: skyDate, compact: true, floatsOnSky: true)
                        .fixedSize()
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $store.showImport) { ImportMusicView() }
        .sheet(isPresented: $store.showCollectionImport) { CollectionImportView() }
        .task(id: store.data.usesWeather) { weather.start(enabled: store.data.usesWeather) }
        .task(id: store.notice) {
            guard store.notice != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            store.notice = nil
        }
        .overlay(alignment: .topTrailing) {
            if let notice = store.notice {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle").foregroundStyle(Palette.accent)
                    Text(notice).font(.system(size: 12)).lineLimit(3).frame(maxWidth: 300, alignment: .leading)
                    IconButton(icon: "xmark", title: "关闭提示") { store.notice = nil }
                }.foregroundStyle(Palette.text).padding(.leading, 16).padding(.trailing, 5).padding(.vertical, 7)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                    .shadow(color: Palette.shadow.opacity(0.05), radius: 12, y: 4)
                    .padding(.top, 8).padding(.trailing, 24)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                LogoMark()
                Text("留白").font(.system(size: 25, weight: .medium)).tracking(4)
            }.padding(.top, 25).padding(.bottom, 14)
            Text("给专注留一点空白").font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.bottom, 30)
            VStack(spacing: 7) {
                ForEach([Screen.focus, .library, .statistics, .journal], id: \.self) { destination in
                    navigation(destination)
                }
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(store.today.focusSeconds / 60))").font(.system(size: 29, weight: .light, design: .rounded)).monospacedDigit()
                    Text("分钟专注").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                HStack(spacing: 5) {
                    ForEach(0..<max(1, store.data.preferences.roundsBeforeLongBreak), id: \.self) { index in
                        Capsule().fill(index < store.today.completedRounds ? Palette.accent : Palette.line).frame(height: 4)
                    }
                }
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 15)).padding(.bottom, 22)
            navigation(.settings).padding(.bottom, 24)
        }.padding(.horizontal, 20).frame(width: 208).background(Palette.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }
    private func navigation(_ destination: Screen) -> some View {
        Button { store.screen = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: destination.icon).font(.system(size: 16, weight: .regular)).frame(width: 22)
                Text(destination.title).font(.system(size: 13, weight: store.screen == destination ? .semibold : .regular))
                Spacer(minLength: 0)
                if store.screen == destination { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
            }.foregroundStyle(store.screen == destination ? Palette.accent : Palette.secondary)
                .padding(.horizontal, 13).padding(.vertical, 13)
                .background(store.screen == destination ? Palette.softAccent : .clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }
    private var header: some View {
        return HStack(alignment: .center, spacing: 12) {
            Button { sidebarCollapsed.toggle() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 32, height: 32)
                    .background(Palette.surface.opacity(0.80), in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
                .help(isSidebarCollapsed ? "展开导航栏 ⌃⌘S" : "折叠导航栏 ⌃⌘S")
                .accessibilityLabel(isSidebarCollapsed ? "展开导航栏" : "折叠导航栏")
                .keyboardShortcut("s", modifiers: [.command, .control])
            if store.screen != .focus {
                Text(store.screen.title).font(.system(size: 27, weight: .semibold))
            }
            Spacer()
            if store.screen == .focus {
                if let weatherOverride {
                    Label("天气预览", systemImage: weatherOverride.precipitation == .snow ? "cloud.snow" : (weatherOverride.precipitation == .rain ? "cloud.rain" : (weatherOverride.windStrength > 0 ? "wind" : "sun.max")))
                        .font(.system(size: 11)).foregroundStyle(Palette.text)
                        .padding(.horizontal, 11).padding(.vertical, 7).background(Palette.surface.opacity(0.82), in: Capsule())
                } else { WeatherChip() }
            }
            Label(store.now.formatted(.dateTime.month(.twoDigits).day(.twoDigits).weekday(.wide).locale(Locale(identifier: "zh_CN"))), systemImage: "sun.max")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                .padding(.horizontal, store.screen == .focus ? 11 : 0)
                .padding(.vertical, store.screen == .focus ? 7 : 0)
                .background {
                    if store.screen == .focus { Capsule().fill(Palette.surface.opacity(0.82)) }
                }
        }.padding(.bottom, store.screen == .focus ? 16 : 25)
    }
    @ViewBuilder private var content: some View {
        switch store.screen {
        case .focus: FocusView(skyDate: skyDate)
        case .library: LibraryView()
        case .statistics: StatisticsView()
        case .journal: JournalView()
        case .settings: PreferencesView()
        }
    }
}

/// Keep native traffic lights and rounded window corners, while letting the
/// page background draw behind the otherwise opaque title-bar material.
struct WindowChromeView: NSViewRepresentable {
    static func configure(_ window: NSWindow) {
        MainWindowPresenter.register(window)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = NSColor(Palette.background)
    }
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) {}
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowChromeView.configure(window) }
        }
    }
}
