import AppKit
import LiuBaiCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { store?.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowPresenter.revealExisting() }
        return true
    }
}

@main
struct LiuBaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()
    init() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-focus-previews"), CommandLine.arguments.indices.contains(index + 1) {
            do { try SkyPreviewExporter.renderFocus(to: CommandLine.arguments[index + 1]); exit(0) }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-sky-previews"), CommandLine.arguments.indices.contains(index + 1) {
            do { try SkyPreviewExporter.render(to: CommandLine.arguments[index + 1]); exit(0) }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        #endif
    }
    var body: some Scene {
        Window("留白", id: "main") {
            RootView().environmentObject(store).environmentObject(store.audio).environmentObject(store.favorites).environmentObject(store.weather)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1200, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands { LiuBaiCommands(store: store) }
        MenuBarExtra {
            MenuBarView().environmentObject(store).environmentObject(store.audio).environmentObject(store.weather)
        } label: {
            if store.data.timer.isRunning { Label(TimeText.clock(store.remaining), systemImage: "leaf") }
            else { Label("留白", systemImage: "leaf") }
        }.menuBarExtraStyle(.window)
    }
}

struct LiuBaiCommands: Commands {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置…") { store.screen = .settings; activateWindow() }.keyboardShortcut(",")
            }
            CommandMenu("专注") {
                Button(store.data.timer.isRunning ? "暂停计时" : "开始 / 继续计时") { store.toggleTimer() }.keyboardShortcut(.return, modifiers: .command)
                Button("播放 / 暂停音乐") { store.togglePlayback() }.keyboardShortcut(.space, modifiers: [.command, .option])
                Divider()
                Button("添加音乐…") { activateWindow(); store.showImport = true }.keyboardShortcut("l")
                Button("专注空间") { store.screen = .focus; activateWindow() }.keyboardShortcut("1")
                Button("我的音乐") { store.screen = .library; activateWindow() }.keyboardShortcut("2")
                Button("时光统计") { store.screen = .statistics; activateWindow() }.keyboardShortcut("3")
                Button("每日手记") { store.screen = .journal; activateWindow() }.keyboardShortcut("4")
            }
    }
    private func activateWindow() {
        MainWindowPresenter.open(using: openWindow)
    }
}

struct MenuBarView: View {
    var skyDate: Date? = nil
    var motionDate: Date? = nil
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var audio: AudioController
    @EnvironmentObject private var weather: WeatherController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let colors = SkyColors(FocusSky(date: skyDate ?? store.now))
        VStack(spacing: 12) {
            HStack {
                Label("留白", systemImage: "leaf")
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Palette.surface.opacity(0.78), in: Capsule())
                Spacer()
                Text(store.data.timer.phase.title)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Palette.surface.opacity(0.78), in: Capsule())
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text)
            Spacer(minLength: 4)
            Text(TimeText.clock(store.remaining))
                .font(.system(size: 39, weight: .light, design: .rounded)).monospacedDigit()
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Palette.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("剩余 \(TimeText.clock(store.remaining))")
            Button { store.toggleTimer() } label: {
                Label(store.data.timer.isRunning ? "暂停计时" : "开始 / 继续", systemImage: store.data.timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 9)
                    .foregroundStyle(.white).background(Palette.accent, in: Capsule())
            }.buttonStyle(.plain)
            Spacer(minLength: 4)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(audio.currentTrack?.title ?? "还没有播放音乐").font(.system(size: 11)).lineLimit(2)
                    Text("今天已完成 \(store.today.completedRounds) 轮").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                IconButton(icon: audio.wantsToPlay ? "pause.fill" : "play.fill", title: "播放或暂停音乐", color: Palette.accent) { store.togglePlayback() }
            }.padding(12).background(Palette.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 13))
            HStack {
                Button { MainWindowPresenter.open(using: openWindow) } label: {
                    Label("打开留白", systemImage: "arrow.up.forward.app")
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Palette.surface.opacity(0.84), in: Capsule())
                }.buttonStyle(.plain)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(colors.ink)
            }.font(.system(size: 11))
        }.padding(18).frame(width: 320, height: 350)
            .background {
                FocusSkyBackground(dateOverride: skyDate, motionOverride: motionDate, weather: weather.visuals, compact: true)
                    .ignoresSafeArea()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Palette.text).tint(Palette.accent).preferredColorScheme(.light)
    }
}
