import AppKit
import LiuBaiCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var section = "音乐"
    private var tracks: [Track] {
        store.myMusic.filter { search.isEmpty || "\($0.title) \($0.artist) \($0.bvid)".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Picker("音乐来源", selection: $section) {
                    Text("我的音乐").tag("音乐")
                    Text("B 站收藏夹").tag("收藏夹")
                    Text("本地合集").tag("合集")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 320)
                Spacer()
                QuietButton(title: "导入合集", icon: "rectangle.stack.badge.plus") { store.showCollectionImport = true }
                PrimaryButton(title: "添加音乐", icon: "plus") { store.showImport = true }
            }
            if section == "收藏夹" {
                FavoritesView().padding(.bottom, 22)
            } else if section == "合集" {
                SavedCollectionsView().padding(.bottom, 22)
            } else {
            HStack(spacing: 16) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                    TextField("搜索音乐…", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Palette.secondary) }
                }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line)).frame(maxWidth: 350)
                Spacer()
                Text("\(store.myMusic.count) 段声音").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Panel(padding: 20) {
                VStack(spacing: 12) {
                    if tracks.isEmpty {
                        Spacer()
                        EmptyNote(icon: search.isEmpty ? "music.note" : "magnifyingglass", title: search.isEmpty ? "暂无音乐" : "未找到音乐", detail: search.isEmpty ? "添加 B 站视频链接或 BV 号。" : "试试标题、UP 主或 BV 号。")
                        if search.isEmpty { QuietButton(title: "添加第一首音乐", icon: "plus") { store.showImport = true }.padding(.top, 10) }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                    TrackRow(track: track, index: index + 1)
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 6) { Image(systemName: "info.circle"); Text("仅显示单独添加的音乐 · 在线播放") }
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.bottom, 22)
            }
        }
    }
}

struct TrackRow: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var audio: AudioController
    let track: Track
    let index: Int
    var queue: [Track]? = nil
    var collectionID: String? = nil
    private var current: Bool { audio.currentTrack?.libraryKey == track.libraryKey }
    var body: some View {
        HStack(spacing: 12) {
            Button { store.play(track, in: queue, collectionID: collectionID) } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11).fill(current ? Palette.softAccent : Palette.background)
                        Image(systemName: current && audio.isPlaying ? "waveform" : "music.note")
                            .font(.system(size: 16, weight: .regular)).foregroundStyle(current ? Palette.accent : Palette.secondary)
                    }.frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.title).font(.system(size: 12, weight: current ? .medium : .regular))
                            .foregroundStyle(current ? Palette.accent : Palette.text).lineLimit(1)
                        Text(track.artist).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 10)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(current && audio.wantsToPlay ? "暂停" : "播放") \(track.title)")
            Text(TimeText.clock(track.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            IconButton(icon: current && audio.wantsToPlay ? "pause.fill" : "play.fill", title: current && audio.wantsToPlay ? "暂停音乐" : "播放音乐", color: Palette.accent) { store.play(track, in: queue, collectionID: collectionID) }
            Menu {
                Button("上移") { store.moveTrack(track, by: -1, in: collectionID) }
                Button("下移") { store.moveTrack(track, by: 1, in: collectionID) }
                Divider()
                Button("复制 B 站链接") {
                    NSPasteboard.general.clearContents()
                    let suffix = (track.page ?? 1) > 1 ? "/?p=\(track.page!)" : "/"
                    NSPasteboard.general.setString("https://www.bilibili.com/video/\(track.bvid)\(suffix)", forType: .string)
                }
                Divider()
                Button(collectionID == nil ? "从我的音乐移除" : "从此合集移除", role: .destructive) { store.removeTrack(track, from: collectionID) }
            } label: { Image(systemName: "ellipsis").foregroundStyle(Palette.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).help("音乐选项")
        }.padding(.horizontal, 9).padding(.vertical, 9)
            .background(current ? Palette.softAccent.opacity(0.32) : .clear, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ImportMusicView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var error: String?
    @State private var working = false
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                LogoMark(size: 44)
                Spacer()
                IconButton(icon: "xmark", title: "关闭添加音乐") { cancel() }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("添加音乐").font(.system(size: 24, weight: .medium))
                Text("粘贴 B 站视频链接、BV / av 号，或 b23.tv 分享链接。")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            TextField("例如：https://www.bilibili.com/video/BV…", text: $input, axis: .vertical)
                .lineLimit(2...3).textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
                .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Palette.accent.opacity(0.65) : Palette.line))
                .disabled(working).onSubmit { add() }
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Palette.warm).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("支持无需登录的公开视频").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer()
                Button("取消") { cancel() }.keyboardShortcut(.cancelAction).buttonStyle(.plain).foregroundStyle(Palette.secondary).padding(.horizontal, 12)
                if working { ProgressView().controlSize(.small).padding(.trailing, 5) }
                PrimaryButton(title: working ? "正在添加…" : "添加到音乐", icon: working ? nil : "plus") { add() }
                    .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(working || input.isEmpty ? 0.55 : 1)
            }
        }.padding(32).frame(width: 560).background(Palette.background).foregroundStyle(Palette.text).tint(Palette.accent)
            .onAppear { focused = true }.onDisappear { task?.cancel() }
    }
    private func add() {
        guard !working, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true; error = nil
        task = Task {
            do {
                try await store.importTrack(input)
                guard !Task.isCancelled else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; working = false
            }
        }
    }
    private func cancel() { task?.cancel(); dismiss() }
}

struct PlayerBar: View {
    var floating = false
    @Environment(\.focusSkySurface) private var skySurface
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var audio: AudioController
    @State private var dragging = false
    @State private var seekPosition: Double = 0
    var body: some View {
        HStack(spacing: floating ? 16 : 22) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.softAccent.opacity(0.7))
                    Image(systemName: "waveform").font(.system(size: 21, weight: .light)).foregroundStyle(Palette.accent)
                }.frame(width: floating ? 38 : 46, height: floating ? 38 : 46)
                VStack(alignment: .leading, spacing: 6) {
                    Text(audio.currentTrack?.title ?? "未播放")
                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if let error = audio.errorMessage {
                        Button { if let track = audio.currentTrack { audio.load(track) } } label: {
                            Label("播放失败，点此重试", systemImage: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(Palette.warm)
                        }.buttonStyle(.plain).help(error)
                    } else {
                        if let artist = audio.currentTrack?.artist {
                            Text(artist).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1)
                        }
                    }
                }
            }.frame(width: floating ? 190 : 240, alignment: .leading)
            VStack(spacing: 3) {
                HStack(spacing: 16) {
                    IconButton(icon: "backward.end.fill", title: "上一首") { store.previousTrack() }.disabled(store.playbackTracks.isEmpty)
                    Button { store.togglePlayback() } label: {
                        ZStack {
                            Circle().fill(Palette.accent).frame(width: 34, height: 34)
                            if audio.isLoading { ProgressView().controlSize(.mini).colorScheme(.dark) }
                            else { Image(systemName: audio.wantsToPlay ? "pause.fill" : "play.fill").font(.system(size: 13)).foregroundStyle(Palette.onAccent).offset(x: audio.wantsToPlay ? 0 : 1) }
                        }
                    }.buttonStyle(.plain).accessibilityLabel(audio.wantsToPlay ? "暂停播放" : "播放音乐")
                    IconButton(icon: "forward.end.fill", title: "下一首") { store.nextTrack() }.disabled(store.playbackTracks.isEmpty)
                }
                HStack(spacing: 9) {
                    Text(TimeText.clock(dragging ? seekPosition : audio.position)).frame(width: 35, alignment: .trailing)
                    Slider(value: Binding(get: { dragging ? seekPosition : min(audio.duration, audio.position) }, set: { seekPosition = $0 }), in: 0...max(1, audio.duration), onEditingChanged: { editing in
                        if editing { seekPosition = audio.position; dragging = true }
                        else { audio.seek(to: seekPosition); dragging = false }
                    }).controlSize(.mini).disabled(audio.currentTrack == nil).accessibilityLabel("音乐播放进度")
                    Text(TimeText.clock(audio.duration)).frame(width: 35, alignment: .leading)
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.secondary)
            }.frame(maxWidth: .infinity)
            HStack(spacing: 9) {
                IconButton(icon: store.data.preferences.repeatTrack ? "repeat.1" : "repeat", title: store.data.preferences.repeatTrack ? "单曲循环，点击切换" : "列表循环，点击切换", color: store.data.preferences.repeatTrack ? Palette.accent : Palette.secondary) {
                    store.updatePreferences { $0.repeatTrack.toggle() }
                }
                Image(systemName: store.data.preferences.volume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Slider(value: Binding(get: { Double(store.data.preferences.volume) }, set: { value in store.updatePreferences { $0.volume = Float(value) } }), in: 0...1)
                    .controlSize(.mini).frame(width: 70).accessibilityLabel("音量")
            }
        }.padding(.horizontal, floating ? 18 : 26).padding(.vertical, floating ? 10 : 14).frame(height: floating ? 76 : 92)
            .background {
                if floating {
                    RoundedRectangle(cornerRadius: 20).fill(Palette.surface.opacity(ThemeOpacity.floatingPlayer))
                        .shadow(color: Palette.shadow.opacity(0.10), radius: 14, y: 4)
                } else { Palette.surface.opacity(skySurface ? 0.90 : 1) }
            }
            .overlay {
                if floating { RoundedRectangle(cornerRadius: 20).stroke(Palette.outline.opacity(ThemeOpacity.floatingPlayerBorder), lineWidth: 1) }
            }
            .overlay(alignment: .top) {
                if !floating { Rectangle().fill(Palette.line).frame(height: 1) }
            }
    }
}
