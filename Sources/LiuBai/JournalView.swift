import LiuBaiCore
import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDate = Date()
    @State private var search = ""
    @State private var confirmDelete = false
    @State private var showMoodEditor = false
    @State private var newMood = ""
    private var moods: [String] {
        let saved = store.data.availableMoods
        return saved.contains(entry.mood) ? saved : saved + [entry.mood]
    }
    private var canSaveMood: Bool {
        let value = newMood.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 12 && !value.contains("\n") && !value.contains("\r")
    }
    private func saveMood() {
        guard canSaveMood, store.addMood(newMood, for: selectedDate) else { return }
        showMoodEditor = false
        newMood = ""
    }
    private var entry: JournalEntry { store.entry(for: selectedDate) }
    private var entries: [JournalEntry] {
        store.data.journal.values.filter { $0.hasContent && (search.isEmpty || "\($0.title) \($0.body) \($0.id)".localizedCaseInsensitiveContains(search)) }
            .sorted { $0.id > $1.id }
    }
    var body: some View {
        let editingDate = selectedDate
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("我的手记").font(.system(size: 14, weight: .medium))
                    Spacer()
                    IconButton(icon: "plus", title: "写今天的手记") { selectedDate = Date() }
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    TextField("搜索手记…", text: $search).textFieldStyle(.plain)
                }.font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(10)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if entries.isEmpty {
                            Text(search.isEmpty ? "暂无手记" : "未找到相关手记")
                                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(6)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 15)
                        }
                        ForEach(entries) { item in
                            Button {
                                if let date = DayKey.date(for: item.id) { selectedDate = date }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.id).font(.system(size: 10)).monospacedDigit()
                                        Spacer()
                                        Circle().fill(item.mood == "低落" ? Palette.secondary : Palette.accent).frame(width: 5, height: 5)
                                    }.foregroundStyle(Palette.secondary)
                                    Text(item.title.isEmpty ? "无题" : item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(item.body.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(2).lineSpacing(3)
                                }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(item.id == entry.id ? Palette.softAccent : Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
            }.frame(width: 195)
            Panel(padding: 27) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        DatePicker("日期", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.field).font(.system(size: 12)).frame(width: 125)
                        if Calendar.current.isDateInToday(selectedDate) {
                            Text("今天").font(.system(size: 10)).foregroundStyle(Palette.accent).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Palette.softAccent, in: Capsule())
                        }
                        Spacer()
                        Menu {
                            Button("导出为 Markdown") { store.exportJournal(for: selectedDate) }
                            Button("删除这篇手记", role: .destructive) { confirmDelete = true }.disabled(!entry.hasContent)
                        } label: { Image(systemName: "ellipsis").foregroundStyle(Palette.secondary) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).help("手记选项")
                    }
                    ComposingTextField(text: Binding(get: { store.entry(for: editingDate).title }, set: { value in store.updateJournal(for: editingDate) { $0.title = value } }), documentID: DayKey.string(for: editingDate), placeholder: "标题（可选）")
                        .frame(height: 32)
                    HStack(spacing: 8) {
                        Text("今天的心情").font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.trailing, 6)
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(moods, id: \.self) { mood in
                                    Button { store.updateJournal(for: selectedDate) { $0.mood = mood } } label: {
                                        Text(mood).font(.system(size: 10)).foregroundStyle(entry.mood == mood ? Palette.accent : Palette.secondary)
                                            .padding(.horizontal, 11).padding(.vertical, 7)
                                            .background(entry.mood == mood ? Palette.softAccent : Palette.background, in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.scrollIndicators(.hidden).frame(height: 30)
                        Button { newMood = ""; showMoodEditor = true } label: {
                            Label("添加心情", systemImage: "plus").font(.system(size: 10)).foregroundStyle(Palette.accent)
                        }.buttonStyle(.plain).fixedSize()
                            .popover(isPresented: $showMoodEditor) {
                                VStack(alignment: .leading, spacing: 14) {
                                    TextField("写个心情，最多 12 字", text: $newMood).textFieldStyle(.roundedBorder).onSubmit(saveMood)
                                    HStack {
                                        Button("取消") { showMoodEditor = false }
                                        Spacer()
                                        Button("保存", action: saveMood).buttonStyle(.borderedProminent).disabled(!canSaveMood)
                                    }
                                }.padding(18).frame(width: 250).tint(Palette.accent)
                            }
                    }
                    let stats = store.stats(for: selectedDate)
                    HStack(spacing: 15) {
                        Label("专注 \(TimeText.duration(stats.focusSeconds))", systemImage: "circle.dotted.circle")
                        Label("完成 \(stats.completedRounds) 轮", systemImage: "checkmark.circle")
                    }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    Rectangle().fill(Palette.line).frame(height: 1)
                    ComposingTextEditor(text: Binding(get: { store.entry(for: editingDate).body }, set: { value in store.updateJournal(for: editingDate) { $0.body = value } }), documentID: DayKey.string(for: editingDate), placeholder: "记录今天…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack {
                        Label(store.savedDescription, systemImage: store.storageError == nil ? "checkmark.circle" : "exclamationmark.circle")
                        Spacer()
                        Text("\(entry.body.count) 字")
                    }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.padding(.bottom, 22)
            .alert("删除这篇手记？", isPresented: $confirmDelete) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { store.deleteJournal(for: selectedDate) }
            } message: { Text("这一天的使用统计仍会保留。删除后无法撤销。") }
    }
}
