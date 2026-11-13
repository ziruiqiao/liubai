import LiuBaiCore
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Panel {
                    VStack(alignment: .leading, spacing: 22) {
                        SectionTitle(title: "番茄钟", subtitle: "时长调整将在下一轮或重置后生效。")
                        HStack(spacing: 24) {
                            durationControl("专注", keyPath: \.focusMinutes, range: 1...180, unit: "分钟")
                            durationControl("短休息", keyPath: \.shortBreakMinutes, range: 1...60, unit: "分钟")
                            durationControl("长休息", keyPath: \.longBreakMinutes, range: 1...90, unit: "分钟")
                            durationControl("长休息间隔", keyPath: \.roundsBeforeLongBreak, range: 1...12, unit: "轮")
                        }
                        Rectangle().fill(Palette.line).frame(height: 1)
                        settingToggle("休息时自动暂停音乐", detail: "关闭时，音乐持续播放。", keyPath: \.pauseMusicDuringBreak)
                        settingToggle("自动开始休息", keyPath: \.autoStartBreak)
                        settingToggle("自动开始下一轮专注", detail: "短休息结束后继续专注。", keyPath: \.autoStartFocus)
                        settingToggle("长休息后自动开始新循环", detail: "关闭时等待手动开始，默认关闭。", keyPath: \.autoStartCycle)
                        settingToggle("阶段结束提示音", detail: "与音乐同时播放。", keyPath: \.soundEnabled)
                        HStack(spacing: 14) {
                            Text("提示音音量").font(.system(size: 12))
                            Spacer()
                            Slider(value: Binding(get: { Double(store.data.preferences.chimeVolume) }, set: { value in store.updatePreferences { $0.chimeVolume = Float(value) } }), in: 0...1).frame(width: 165)
                            Text("\(Int(store.data.preferences.chimeVolume * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary).frame(width: 38, alignment: .trailing)
                            QuietButton(title: "试听", icon: "speaker.wave.2") { store.previewCompletionSound() }
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 21) {
                        SectionTitle(title: "播放")
                        settingToggle("单曲循环", detail: "关闭时按当前列表循环。", keyPath: \.repeatTrack)
                        HStack {
                            Text("默认音量").font(.system(size: 13))
                            Spacer()
                            Slider(value: Binding(get: { Double(store.data.preferences.volume) }, set: { value in store.updatePreferences { $0.volume = Float(value) } }), in: 0...1).frame(width: 165)
                            Text("\(Int(store.data.preferences.volume * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary).frame(width: 38, alignment: .trailing)
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle(title: "本地数据", subtitle: "保存在这台 Mac，保存时保留上一份备份。")
                        HStack(spacing: 11) {
                            QuietButton(title: "导出全部数据", icon: "square.and.arrow.up") { store.exportData() }
                            QuietButton(title: "打开数据文件夹", icon: "folder") { store.showDataInFinder() }
                        }
                        Text("关闭窗口后继续播放和计时；退出 App 或休眠时暂停。").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(5)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Panel { WeatherSettingsPanel() }
                HStack(alignment: .center, spacing: 14) {
                    LogoMark(size: 38)
                    Text("留白 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · macOS").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Link("参考项目 biu ↗", destination: URL(string: "https://github.com/wood3n/biu")!)
                        .font(.system(size: 10)).foregroundStyle(Palette.accent)
                }.padding(5)
            }.padding(.bottom, 24).padding(.horizontal, 1)
        }.scrollIndicators(.hidden)
    }
    private func durationControl(_ title: String, keyPath: WritableKeyPath<Preferences, Int>, range: ClosedRange<Int>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            HStack(spacing: 7) {
                TextField(title, value: Binding(get: { store.data.preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, value)) } }), format: .number)
                    .textFieldStyle(.plain).font(.system(size: 26, weight: .light, design: .rounded)).monospacedDigit().frame(minWidth: 35)
                    .accessibilityLabel("\(title)时长")
                Text(unit).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Stepper(title, value: Binding(get: { store.data.preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } }), in: range)
                    .labelsHidden().controlSize(.small)
            }.padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 11))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func settingToggle(_ title: String, detail: String? = nil, keyPath: WritableKeyPath<Preferences, Bool>) -> some View {
        Toggle(isOn: Binding(get: { store.data.preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            }
        }.toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
    }
}
