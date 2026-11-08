import LiuBaiCore
import SwiftUI

struct FocusRecordsPanel: View {
    @EnvironmentObject private var store: AppStore
    @State private var date = Date()

    var body: some View {
        Panel(padding: 22) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    SectionTitle(title: "专注时间块")
                    Spacer()
                    DatePicker("记录日期", selection: $date, in: ...store.now, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field).frame(width: 130)
                }
                let records = store.data.focusRecords(on: date)
                if records.isEmpty {
                    Text("这一天还没有专注时间块")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.vertical, 10)
                }
                ForEach(records) { record in
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(time(record.startedAt)).font(.system(size: 14, weight: .medium, design: .rounded))
                            Text("至 \(time(record.endedAt))").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }.monospacedDigit().frame(width: 65, alignment: .leading)
                        RoundedRectangle(cornerRadius: 2).fill(Palette.accent.opacity(0.55)).frame(width: 3, height: 37)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.intention.isEmpty ? "未填写目标" : record.intention)
                                .font(.system(size: 13)).lineLimit(3).textSelection(.enabled)
                                .help(record.intention)
                            Text(status(record)).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(TimeText.duration(record.focusSeconds)).font(.system(size: 12)).foregroundStyle(Palette.accent)
                            .monospacedDigit().help("实际专注时长，不含暂停")
                    }.padding(14).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
    private func status(_ record: FocusBlockDay) -> String {
        if record.isOpen {
            guard record.day == DayKey.string(for: store.now) else { return "已记录" }
            return store.data.timer.isRunning && store.data.timer.phase == .focus ? "进行中" : "已暂停"
        }
        return record.completed ? "已完成" : "已结束"
    }
}
