import LiuBaiCore
import SwiftUI

struct CollectionImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var preview: LibraryPreview?
    @State private var working = false
    @State private var progress = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview == nil ? "导入合集" : "选择音乐").font(.system(size: 23, weight: .medium))
                    Text("只加入播放信息，不下载音频文件。").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                IconButton(icon: "xmark", title: "关闭导入合集") { task?.cancel(); dismiss() }
            }
            if let preview {
                LibraryPreviewView(preview: preview) { dismiss() }.frame(height: 435)
            } else {
                TextField("粘贴 UP 主合集、系列或分 P 视频链接…", text: $input, axis: .vertical)
                    .lineLimit(2...3).textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
                    .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Palette.accent.opacity(0.6) : Palette.line))
                    .disabled(working).onSubmit { read() }
                Text("属于合集的视频链接也可自动读取整个合集。")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Palette.warm).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    if working { ProgressView().controlSize(.small); Text(progress).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                    Spacer()
                    Button("取消") { task?.cancel(); dismiss() }.buttonStyle(.plain).keyboardShortcut(.cancelAction).foregroundStyle(Palette.secondary).padding(.trailing, 10)
                    PrimaryButton(title: working ? "正在读取…" : "读取合集", icon: working ? nil : "arrow.down.right") { read() }
                        .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).opacity(working || input.isEmpty ? 0.55 : 1)
                }
            }
        }.padding(30).frame(width: 650).background(Palette.background).foregroundStyle(Palette.text).tint(Palette.accent)
            .preferredColorScheme(.light).onAppear { focused = true }.onDisappear { task?.cancel() }
    }
    private func read() {
        guard !working, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true; error = nil; progress = "正在读取列表…"
        task = Task {
            do {
                let result = try await store.client.collection(input) { count, total in
                    await MainActor.run { progress = "已读取 \(count) / \(total) 段声音" }
                }
                guard !Task.isCancelled else { return }
                preview = result; working = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; working = false
            }
        }
    }
}

struct LibraryPreviewView: View {
    @EnvironmentObject private var store: AppStore
    let preview: LibraryPreview
    let onImported: () -> Void
    @State private var selected = Set<String>()
    private var alreadySaved: Set<String> { Set(store.collections.first(where: { $0.id == preview.id })?.trackKeys ?? []) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(preview.title).font(.system(size: 15, weight: .medium)).lineLimit(2)
                    Text("\(preview.kind.title) · \(preview.tracks.count) 段声音\(preview.skippedCount > 0 ? " · \(preview.skippedCount) 个失效或不支持的条目已跳过" : "")")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
            }
            HStack(spacing: 13) {
                Button(selected.count == preview.tracks.count ? "取消全选" : "全选") {
                    selected = selected.count == preview.tracks.count ? [] : Set(preview.tracks.map(\.libraryKey))
                }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                Text("已选 \(selected.count) 段").foregroundStyle(Palette.secondary)
                Spacer()
                Text("此合集内已有的音乐会自动去重").foregroundStyle(Palette.secondary)
            }.font(.system(size: 11))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(preview.tracks) { track in
                        Button {
                            if selected.contains(track.libraryKey) { selected.remove(track.libraryKey) }
                            else { selected.insert(track.libraryKey) }
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: selected.contains(track.libraryKey) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(track.libraryKey) ? Palette.accent : Palette.line).font(.system(size: 17))
                                Text(track.title).font(.system(size: 11)).foregroundStyle(Palette.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                if alreadySaved.contains(track.libraryKey) { Text("已加入").font(.system(size: 9)).foregroundStyle(Palette.secondary) }
                                Text(TimeText.clock(track.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                            }.padding(.vertical, 11).padding(.horizontal, 10).contentShape(Rectangle())
                                .background(selected.contains(track.libraryKey) ? Palette.softAccent.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityLabel("\(selected.contains(track.libraryKey) ? "已选择" : "未选择") \(track.title)")
                    }
                }
            }.scrollIndicators(.hidden).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("保存为本地合集，不加入“我的音乐”。").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer()
                PrimaryButton(title: "加入 \(selected.count) 段声音", icon: "plus") {
                    store.importCollection(preview, selected: selected)
                    onImported()
                }.disabled(selected.isEmpty).opacity(selected.isEmpty ? 0.55 : 1)
            }
        }.onAppear { selected = Set(preview.tracks.map(\.libraryKey)) }
    }
}
