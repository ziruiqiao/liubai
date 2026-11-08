import LiuBaiCore
import SwiftUI

struct WeatherSettingsPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var weather: WeatherController
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Toggle("天气背景", isOn: Binding(get: { store.data.usesWeather }, set: { store.setWeatherEnabled($0) }))
                .toggleStyle(.switch).font(.system(size: 13))
            if store.data.usesWeather {
                HStack {
                    Label(weather.label, systemImage: weather.freshSnapshot?.icon ?? "location")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Spacer()
                    if weather.isLoading { ProgressView().controlSize(.small) }
                    if weather.needsLocationSettings {
                        QuietButton(title: "定位设置", icon: "location") { weather.openLocationSettings() }
                    } else {
                        QuietButton(title: weather.freshSnapshot == nil ? "获取天气" : "刷新", icon: "arrow.clockwise") { weather.refresh() }
                            .disabled(weather.isLoading)
                    }
                }
                if let error = weather.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            }
            Text("跟随 Mac 系统定位，仅使用城市级位置，约 15 分钟更新。")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Link("天气数据 Open-Meteo · CC BY 4.0", destination: URL(string: "https://open-meteo.com/")!)
                .font(.system(size: 10)).foregroundStyle(Palette.accent)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WeatherSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("天气背景").font(.system(size: 22, weight: .medium))
                Spacer()
                IconButton(icon: "xmark", title: "关闭天气设置") { dismiss() }
            }
            WeatherSettingsPanel()
        }.padding(26).frame(width: 470).background(Palette.background)
            .foregroundStyle(Palette.text).tint(Palette.accent).preferredColorScheme(.light)
    }
}

struct WeatherChip: View {
    @EnvironmentObject private var weather: WeatherController
    @State private var showSettings = false
    var body: some View {
        Button { showSettings = true } label: {
            Label(weather.label, systemImage: weather.isEnabled ? (weather.freshSnapshot?.icon ?? "location") : "cloud.sun")
                .font(.system(size: 11)).lineLimit(1).foregroundStyle(Palette.text)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Palette.surface.opacity(0.82), in: Capsule())
        }.buttonStyle(.plain).help(weather.detail)
            .sheet(isPresented: $showSettings) { WeatherSettingsView() }
    }
}
