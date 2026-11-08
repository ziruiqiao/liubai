import LiuBaiCore
import SwiftUI

struct SkyPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var weather: WeatherController
    @State private var hour = FocusSky(date: Date()).localHour
    @State private var speed = 1.0
    @State private var moving = true
    @State private var frozenMotion = Date()
    @State private var weatherMode = "当前"
    @State private var showsTimerCard = false

    init(hour: Double? = nil, weatherMode: String = "当前", showsTimerCard: Bool = false) {
        _hour = State(initialValue: hour ?? FocusSky(date: Date()).localHour)
        _weatherMode = State(initialValue: weatherMode)
        _showsTimerCard = State(initialValue: showsTimerCard)
    }
    private var previewWeather: SkyWeather {
        switch weatherMode {
        case "晴": return .clear
        case "多云": return .cloudyPreview
        case "雨": return .rainPreview
        case "暴雨": return .heavyRainPreview
        case "雪": return .snowPreview
        case "暴雪": return .heavySnowPreview
        case "风": return .windPreview
        default: return weather.visuals
        }
    }
    private let presets: [(String, Double)] = [("清晨", 6.5), ("上午", 9), ("正午", 12), ("黄昏", 17.5), ("夜晚", 21), ("午夜", 0)]
    private var previewDate: Date {
        let calendar = Calendar.autoupdatingCurrent
        let whole = Int(hour) % 24
        let minute = min(59, Int((hour - floor(hour)) * 60))
        return calendar.date(bySettingHour: whole, minute: minute, second: 0, of: Date()) ?? Date()
    }
    private var timeText: String { String(format: "%02d:%02d", Int(hour) % 24, Int(hour * 60) % 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("天空预览").font(.system(size: 23, weight: .medium))
                    Text("预览不影响音乐和计时。")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                IconButton(icon: "xmark", title: "关闭天空预览") { dismiss() }
            }
            HStack(spacing: 8) {
                ForEach(presets, id: \.0) { name, value in
                    Button { hour = value } label: {
                        Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(abs(hour - value) < 0.1 ? Palette.accent : Palette.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(abs(hour - value) < 0.1 ? Palette.softAccent : Palette.surface, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button("现在") { hour = FocusSky(date: Date()).localHour }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
            }
            Picker("预览天气", selection: $weatherMode) {
                ForEach(["当前", "晴", "多云", "雨", "暴雨", "雪", "暴雪", "风"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("预览天气效果，不改变实际天气")
            ZStack(alignment: .bottomTrailing) {
                FocusSkyBackground(dateOverride: previewDate, motionOverride: moving ? nil : frozenMotion, motionRate: speed, weather: previewWeather)
                if showsTimerCard {
                    TimerPanel(skyDate: previewDate, offersSkyPreview: false, compact: true)
                        .frame(width: 360)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(0.46, anchor: .bottomTrailing)
                        .frame(width: 166, height: 205, alignment: .bottomTrailing)
                        .padding(18)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityLabel("天空动画预览")
            HStack(spacing: 14) {
                Text(timeText).font(.system(size: 18, weight: .light, design: .rounded)).monospacedDigit().frame(width: 53)
                Slider(value: $hour, in: 0...23.99).accessibilityLabel("预览本地时间，0 至 24 点")
                Text("24 时").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 13) {
                QuietButton(title: moving ? "暂停动画" : "继续动画", icon: moving ? "pause.fill" : "play.fill") {
                    if moving { frozenMotion = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate * speed) }
                    moving.toggle()
                }
                Picker("动画速度", selection: $speed) {
                    Text("正常").tag(1.0)
                    Text("8 倍预览").tag(8.0)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
                Spacer()
                Toggle("计时卡片", isOn: $showsTimerCard).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
            }
        }.padding(22).frame(width: 700).background(Palette.background).foregroundStyle(Palette.text).tint(Palette.accent).preferredColorScheme(.light)
            .onExitCommand { dismiss() }
    }
}
