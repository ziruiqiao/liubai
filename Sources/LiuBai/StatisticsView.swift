import Charts
import LiuBaiCore
import SwiftUI

private enum StatisticMetric: String, CaseIterable {
    case focus = "专注", listening = "收听", usage = "使用"
    func seconds(in item: DailyStats) -> TimeInterval {
        switch self { case .focus: return item.focusSeconds; case .listening: return item.listeningSeconds; case .usage: return item.usageSeconds }
    }
}

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var days = 7
    @State private var metric: StatisticMetric = .focus
    private var dates: [Date] {
        (0..<days).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: store.now)) }
    }
    private var records: [DailyStats] { dates.map { store.stats(for: $0) } }
    private var focus: TimeInterval { records.reduce(0) { $0 + $1.focusSeconds } }
    private var listening: TimeInterval { records.reduce(0) { $0 + $1.listeningSeconds } }
    private var usage: TimeInterval { records.reduce(0) { $0 + $1.usageSeconds } }
    private var rounds: Int { records.reduce(0) { $0 + $1.completedRounds } }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Picker("统计范围", selection: $days) { Text("近 7 天").tag(7); Text("近 30 天").tag(30) }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
                    QuietButton(title: "导出数据", icon: "square.and.arrow.up") { store.exportData() }
                }
                HStack(spacing: 13) {
                    metricCard(title: "使用时长", value: usage, icon: "clock", color: Palette.secondary)
                    metricCard(title: "专注时长", value: focus, icon: "circle.dotted.circle", color: Palette.accent)
                    metricCard(title: "收听时长", value: listening, icon: "headphones", color: Palette.warm)
                    Panel(padding: 19) {
                        VStack(alignment: .leading, spacing: 15) {
                            Label("完成番茄", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(Palette.accent)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(rounds)").font(.system(size: 29, weight: .light, design: .rounded)).monospacedDigit()
                                Text("轮").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                            }
                            Text("\(records.filter(\.usedPomodoro).count) 天用过番茄钟").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                FocusRecordsPanel()
                Panel {
                    VStack(alignment: .leading, spacing: 25) {
                        HStack {
                            SectionTitle(title: "趋势")
                            Spacer()
                            Picker("查看指标", selection: $metric) { ForEach(StatisticMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                        }
                        Chart(dates, id: \.self) { date in
                            BarMark(x: .value("日期", date, unit: .day), y: .value("分钟", metric.seconds(in: store.stats(for: date)) / 60), width: .ratio(days == 7 ? 0.38 : 0.6))
                                .foregroundStyle(Palette.accent.gradient).cornerRadius(4)
                        }
                        .chartYScale(domain: 0...max(30, (records.map { metric.seconds(in: $0) / 60 }.max() ?? 0) * 1.15))
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 5)) { _ in
                                AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine().foregroundStyle(Palette.line)
                                AxisValueLabel { if let number = value.as(Double.self) { Text("\(Int(number)) 分").font(.system(size: 9)).foregroundStyle(Palette.secondary) } }
                            }
                        }.frame(height: 195)
                        if records.allSatisfy({ metric.seconds(in: $0) == 0 }) {
                            Text("暂无\(metric.rawValue)记录").font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
                        }
                    }
                }
                Panel(padding: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle(title: "每日记录")
                        HStack {
                            Text("日期").frame(maxWidth: .infinity, alignment: .leading)
                            Text("使用").frame(width: 105, alignment: .trailing)
                            Text("收听").frame(width: 105, alignment: .trailing)
                            Text("专注").frame(width: 105, alignment: .trailing)
                            Text("番茄钟").frame(width: 98, alignment: .trailing)
                        }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        ForEach(Array(dates.reversed().prefix(7)), id: \.self) { date in
                            let record = store.stats(for: date)
                            VStack(spacing: 13) {
                                Rectangle().fill(Palette.line).frame(height: 1)
                                HStack {
                                    Text(Calendar.current.isDateInToday(date) ? "今天" : date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(TimeText.duration(record.usageSeconds)).frame(width: 105, alignment: .trailing)
                                    Text(TimeText.duration(record.listeningSeconds)).frame(width: 105, alignment: .trailing)
                                    Text(TimeText.duration(record.focusSeconds)).frame(width: 105, alignment: .trailing)
                                    Text(record.usedPomodoro ? "\(record.completedRounds) 轮完成" : "未使用").foregroundStyle(record.usedPomodoro ? Palette.accent : Palette.secondary).frame(width: 98, alignment: .trailing)
                                }.font(.system(size: 11)).monospacedDigit()
                            }
                        }
                    }
                }
                Text("使用时长不重复累计；完整结束的专注计入轮数，休眠期间不记录。")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom, 24).padding(.horizontal, 1)
        }.scrollIndicators(.hidden)
    }
    private func metricCard(title: String, value: TimeInterval, icon: String, color: Color) -> some View {
        Panel(padding: 19) {
            VStack(alignment: .leading, spacing: 15) {
                Label(title, systemImage: icon).font(.system(size: 11)).foregroundStyle(color)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(value / 60))").font(.system(size: 29, weight: .light, design: .rounded)).monospacedDigit()
                    Text("分钟").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Text("最近 \(days) 天").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
