import LiuBaiCore
import SwiftUI

struct SavedCollectionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: String?
    @State private var removal: LibraryCollection?
    private var selected: LibraryCollection? { store.collections.first(where: { $0.id == selectedID }) ?? store.collections.first }
    var body: some View {
        if store.collections.isEmpty {
            Panel {
                VStack(spacing: 20) {
                    Spacer()
                    EmptyNote(icon: "rectangle.stack", title: "暂无本地合集", detail: "导入 UP 主合集、系列或收藏夹。")
                    QuietButton(title: "导入第一个合集", icon: "plus") { store.showCollectionImport = true }
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            HStack(alignment: .top, spacing: 17) {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(store.collections) { group in
                            Button { selectedID = group.id } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    Image(systemName: group.kind == .favorites ? "folder" : "rectangle.stack").font(.system(size: 18, weight: .light)).foregroundStyle(Palette.accent)
                                    Text(group.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text).lineLimit(3)
                                    Text("\(store.tracks(in: group).count) 段声音 · \(group.kind.title)").font(.system(size: 9)).foregroundStyle(Palette.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                                    .background(selected?.id == group.id ? Palette.softAccent : Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden).frame(width: 187)
                if let selected {
                    let tracks = store.tracks(in: selected)
                    Panel(padding: 20) {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top) {
                                SectionTitle(title: selected.title, subtitle: "\(tracks.count) 段声音 · \(selected.kind.title)")
                                Spacer()
                                Menu {
                                    Button("移除此本地合集") { removal = selected }
                                } label: { Image(systemName: "ellipsis").foregroundStyle(Palette.secondary) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                            }
                            QuietButton(title: "播放整个合集", icon: "play.fill") { store.playCollection(selected) }.disabled(tracks.isEmpty)
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                        TrackRow(track: track, index: index + 1, queue: tracks, collectionID: selected.id)
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .alert("移除此本地合集？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
                Button("取消", role: .cancel) { removal = nil }
                Button("移除", role: .destructive) { if let removal { store.removeCollection(removal) }; removal = nil }
            } message: { Text("同时移除仅属于此合集的本地播放信息。单独添加的音乐、其他合集里的音乐，以及 B 站上的内容都会保留。") }
        }
    }
}
