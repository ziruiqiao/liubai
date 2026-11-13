import LiuBaiCore
import SwiftUI

struct FocusView: View {
    var skyDate: Date? = nil
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var audio: AudioController
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                TodayPanel()
                intentionPanel
                musicPanel
                Spacer(minLength: 12)
                TimerPanel(skyDate: skyDate, compact: true, controlsOnly: true)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(width: 268)
        }.padding(.bottom, 18)
    }
    private var musicPanel: some View {
        let track = audio.currentTrack ?? store.myMusic.first
        return Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("音乐").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button("音乐库") { store.screen = .library }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
                    IconButton(icon: "plus", title: "添加音乐") { store.showImport = true }
                }
                Button {
                    if audio.currentTrack != nil { store.togglePlayback() }
                    else if let track { store.play(track) }
                    else { store.showImport = true }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track?.title ?? "添加音乐").font(.system(size: 11)).lineLimit(2).foregroundStyle(Palette.text)
                            if let track { Text(track.artist).font(.system(size: 10)).lineLimit(1).foregroundStyle(Palette.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: track == nil ? "plus.circle" : (audio.wantsToPlay ? "pause.circle.fill" : "play.circle.fill"))
                            .font(.system(size: 29, weight: .light)).foregroundStyle(Palette.accent)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
    private var intentionPanel: some View {
        Panel(padding: 16) {
            ComposingTextEditor(text: Binding(get: { store.data.intention }, set: store.updateIntention), documentID: "focus-intention", lineSpacing: 5, inset: .zero, accessibilityLabel: "当前目标", placeholder: "写下此刻的目标…")
                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 44)
        }
    }
}

struct TimerPanel: View {
    var skyDate: Date? = nil
    var motionDate: Date? = nil
    var motionRate: Double = 1
    var offersSkyPreview = true
    var compact = false
    var fillsHeight = false
    var controlsOnly = false
    @EnvironmentObject private var store: AppStore
    @State private var showReset = false
    @State private var pendingPhase: TimerPhase?
    @State private var showPhaseChange = false
    @State private var showSkyPreview = false
    var body: some View {
        let date = skyDate ?? store.now
        let sky = FocusSky(date: date)
        let colors = TimerColors()
        let clockText = date.formatted(date: .omitted, time: .shortened)
            VStack(spacing: compact ? 12 : 20) {
                HStack {
                    if !controlsOnly { Label("番茄钟", systemImage: "timer").font(.system(size: 13, weight: .medium)) }
                    if !controlsOnly { Spacer() }
                    if offersSkyPreview {
                        Button { showSkyPreview = true } label: {
                            Label("预览天空", systemImage: "eye").font(.system(size: 10))
                        }.buttonStyle(.plain).foregroundStyle(colors.secondary).help("自行查看日间、夜间和动画效果")
                    }
                    if controlsOnly { Spacer(minLength: 8) }
                    Text("本地 \(clockText)")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(colors.secondary)
                    if !controlsOnly { IconButton(icon: "slider.horizontal.3", title: "调整番茄钟", color: colors.secondary) { store.screen = .settings } }
                }.padding(.leading, controlsOnly ? 0 : 10).padding(.trailing, controlsOnly ? 0 : 2)
                    .background {
                        if !controlsOnly {
                            RoundedRectangle(cornerRadius: 10).fill(colors.face.opacity(sky.daylight >= 0.5 ? 0.42 : 0.72))
                        }
                    }
                HStack(spacing: 3) {
                    ForEach(TimerPhase.allCases, id: \.self) { phase in
                        Button {
                            guard phase != store.data.timer.phase else { return }
                            if store.data.timer.hasStarted { pendingPhase = phase; showPhaseChange = true }
                            else { store.selectPhase(phase) }
                        } label: {
                            Text(phase.title).font(.system(size: 12, weight: store.data.timer.phase == phase ? .medium : .regular))
                                .foregroundStyle(store.data.timer.phase == phase ? colors.ink : colors.secondary)
                                .frame(width: controlsOnly ? 66 : 76).padding(.vertical, 9)
                                .background(store.data.timer.phase == phase ? colors.face.opacity(0.94) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }.padding(4).background(colors.controls.opacity(sky.daylight >= 0.5 ? 0.60 : 0.86), in: RoundedRectangle(cornerRadius: 11))
                if fillsHeight { Spacer(minLength: 4) }
                if !controlsOnly { TimerDial(skyDate: skyDate, compact: compact) }
                if fillsHeight { Spacer(minLength: 4) }
                HStack(spacing: controlsOnly ? 8 : 14) {
                    IconButton(icon: "arrow.counterclockwise", title: "重置这一轮", color: colors.secondary) {
                        if store.data.timer.hasStarted { showReset = true } else { store.resetTimer() }
                    }
                    PrimaryButton(title: store.data.timer.isRunning ? "暂停" : (store.data.timer.hasStarted ? "继续" : (store.data.timer.phase == .focus ? "开始专注" : "开始休息")),
                                  icon: store.data.timer.isRunning ? "pause.fill" : "play.fill") { store.toggleTimer() }
                        .frame(minWidth: controlsOnly ? 112 : 156)
                    IconButton(icon: "gearshape", title: "番茄钟设置", color: colors.secondary) { store.screen = .settings }
                }
                HStack(spacing: 7) {
                    ForEach(0..<max(1, store.data.preferences.roundsBeforeLongBreak), id: \.self) { index in
                        Circle().fill(index < store.data.timer.completedInCycle ? colors.accent : colors.track.opacity(0.55)).frame(width: 7, height: 7)
                    }
                    Text(store.data.timer.phase == .longBreak ? "一轮循环已完成" : "第 \(store.data.timer.completedInCycle + 1) / \(store.data.preferences.roundsBeforeLongBreak) 轮")
                        .font(.system(size: 10)).foregroundStyle(colors.secondary).padding(.leading, 4)
                }.padding(.horizontal, 11).padding(.vertical, 5)
                    .background(colors.face.opacity(0.40), in: Capsule())
            }.frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil).foregroundStyle(colors.ink).padding(controlsOnly ? 12 : (compact ? 18 : 25))
        .background(Palette.surface.opacity(ThemeOpacity.timerCard))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.outline.opacity(sky.isDay ? 0.55 : 0.13), lineWidth: 1))
        .sheet(isPresented: $showSkyPreview) { SkyPreviewView() }
        .alert("重新开始这一轮？", isPresented: $showReset) {
            Button("取消", role: .cancel) {}
            Button("重置计时") { store.resetTimer() }
        } message: { Text("已专注的时长会保留，这一轮不会计入完成轮数。") }
        .alert("切换计时阶段？", isPresented: $showPhaseChange) {
            Button("取消", role: .cancel) { pendingPhase = nil }
            Button("切换并重置") { if let pendingPhase { store.selectPhase(pendingPhase) }; pendingPhase = nil }
        } message: { Text("当前阶段将结束，已记录的专注时长会保留。") }
    }
}

struct TimerDial: View {
    var skyDate: Date? = nil
    var compact = false
    var floatsOnSky = false
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let sky = FocusSky(date: skyDate ?? store.now)
        let colors = TimerColors()
        let skyColors = OverlayColors(sky)
        let ink = floatsOnSky ? skyColors.ink : colors.ink
        let secondary = floatsOnSky ? skyColors.secondary : colors.secondary
        let accent = floatsOnSky ? skyColors.accent : colors.accent
        let track = floatsOnSky ? skyColors.track : colors.track
                ZStack {
                    if !floatsOnSky { Circle().fill(colors.face.opacity(0.82))
                        .shadow(color: Palette.shadow.opacity(sky.isDay ? 0.025 : 0.10), radius: 16, y: 5)
                    }
                    Circle().stroke(track.opacity(0.55), lineWidth: 5)
                    Circle().trim(from: 0, to: max(0.002, store.timerProgress))
                        .stroke(store.data.timer.phase == .focus ? accent : Palette.restAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 10) {
                        Text(store.data.timer.phase == .focus ? "把此刻留给自己" : "休息也是节奏的一部分")
                            .font(.system(size: 11)).foregroundStyle(secondary)
                        Text(TimeText.clock(store.remaining))
                            .font(.system(size: compact ? 50 : 58, weight: .ultraLight, design: .rounded)).monospacedDigit().tracking(1)
                            .contentTransition(.numericText()).accessibilityLabel("剩余 \(TimeText.clock(store.remaining))")
                        Text(store.data.timer.isRunning ? (store.data.timer.phase == .focus ? "正在专注" : "正在休息") : (store.data.timer.hasStarted ? "已暂停" : "未开始"))
                            .font(.system(size: 11)).foregroundStyle(secondary)
                    }
                }.frame(width: compact ? 200 : 235, height: compact ? 200 : 235).padding(.vertical, 1)
            .foregroundStyle(ink)
    }
}

struct TodayPanel: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(store.today.focusSeconds / 60))").font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
                    Text("分钟专注").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack {
                    smallMetric(value: "\(store.today.completedRounds)", unit: "轮完成")
                    Spacer()
                    smallMetric(value: "\(Int(store.today.listeningSeconds / 60))", unit: "分钟收听")
                }
                HStack {
                    Text("今日使用 \(TimeText.duration(store.today.usageSeconds))").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button { store.screen = .statistics } label: { Image(systemName: "arrow.up.right").font(.system(size: 11)) }.buttonStyle(.plain).help("查看时光统计")
                }
            }
        }
    }
    private func smallMetric(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 19, weight: .light, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }
    }
}
