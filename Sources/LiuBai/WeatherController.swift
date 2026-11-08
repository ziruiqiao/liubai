import AppKit
import Combine
import CoreLocation
import Foundation
import LiuBaiCore
import OSLog

@MainActor
final class WeatherController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var city = "本地"
    @Published private(set) var status = "跟随系统定位"
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isEnabled = false
    @Published private(set) var needsLocationSettings = false
    private let client = WeatherClient()
    private let logger = Logger(subsystem: "app.liubai.mac", category: "weather")
    private var manager: CLLocationManager?
    private let geocoder = CLGeocoder()
    private var coordinate: WeatherCoordinate?
    private var forecastTask: Task<Void, Never>?
    private var cityTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var locationTimeout: Task<Void, Never>?
    private var generation = UUID()
    private let isPreview = CommandLine.arguments.contains("--render-focus-previews") || CommandLine.arguments.contains("--render-sky-previews")

    var freshSnapshot: WeatherSnapshot? { snapshot.flatMap { $0.isFresh(at: Date()) ? $0 : nil } }
    var visuals: SkyWeather { isEnabled ? (freshSnapshot?.visuals ?? .clear) : .clear }
    var label: String {
        if let value = freshSnapshot { return "\(city)  \(Int(value.temperature.rounded()))° · \(value.description)" }
        return status
    }
    var detail: String {
        if let value = freshSnapshot {
            let time = value.modelTime.formatted(date: .omitted, time: .shortened)
            return "\(city) · \(value.description) · 风速 \(Int(value.windKmh.rounded())) km/h\n天气时刻 \(time)\(error == nil ? "" : " · 更新暂不可用")\n天气数据：Open-Meteo"
        }
        return error ?? status
    }

    func start(enabled: Bool) {
        guard enabled else { stop(); isEnabled = false; return }
        guard !isEnabled else { return }
        isEnabled = true
        guard !isPreview else { return }
        requestLocation()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15 * 60)) } catch { return }
                self?.refresh(force: false)
            }
        }
    }

    func stop() {
        forecastTask?.cancel(); forecastTask = nil
        cityTask?.cancel(); cityTask = nil
        refreshTask?.cancel(); refreshTask = nil
        locationTimeout?.cancel(); locationTimeout = nil
        manager?.stopUpdatingLocation()
        geocoder.cancelGeocode()
        generation = UUID()
        snapshot = nil; coordinate = nil; city = "本地"
        isLoading = false; isEnabled = false; error = nil
        status = "天气已关闭"
    }

    func requestLocation(allowPrompt: Bool = true) {
        guard isEnabled, !isPreview else { return }
        if manager == nil {
            let manager = CLLocationManager()
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = 10_000
            self.manager = manager
            manager.delegate = self
        }
        updateAuthorization(allowPrompt: allowPrompt)
    }

    private func updateAuthorization(allowPrompt: Bool) {
        guard isEnabled, let manager else { return }
        let locationEnabled = CLLocationManager.locationServicesEnabled()
        logger.notice("System location enabled: \(locationEnabled, privacy: .public); authorization: \(manager.authorizationStatus.rawValue, privacy: .public)")
        guard locationEnabled else {
            forecastTask?.cancel(); cityTask?.cancel(); geocoder.cancelGeocode(); generation = UUID()
            manager.stopUpdatingLocation(); snapshot = nil; coordinate = nil; city = "本地"
            needsLocationSettings = true; isLoading = false
            status = "系统定位已关闭"; return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            needsLocationSettings = false
            status = "允许定位以显示天气"
            // Native macOS prompts when a location service starts; the
            // requestWhenInUseAuthorization flow is intended for UIKit apps.
            if allowPrompt { manager.startUpdatingLocation() }
        case .restricted, .denied:
            forecastTask?.cancel(); cityTask?.cancel(); geocoder.cancelGeocode(); generation = UUID()
            needsLocationSettings = true; isLoading = false
            status = "需允许定位"; manager.stopUpdatingLocation()
            snapshot = nil; coordinate = nil; city = "本地"
        case .authorizedAlways:
            needsLocationSettings = false
            status = coordinate == nil ? "正在获取城市…" : status
            manager.startUpdatingLocation()
            locationTimeout?.cancel()
            locationTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.coordinate == nil else { return }
                self.status = "定位暂不可用"
                self.error = "请检查 Mac 的定位服务和网络连接。"
            }
        @unknown default: status = "定位暂不可用"
        }
    }

    func refresh(force: Bool = true) {
        guard isEnabled, !isPreview else { return }
        if let coordinate { fetch(coordinate, force: force) }
        else { requestLocation(allowPrompt: force) }
    }

    func openLocationSettings() {
        let target = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        if !NSWorkspace.shared.open(target) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.updateAuthorization(allowPrompt: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // The exact coordinate is discarded here, rather than stored in the
        // controller or passed to any network client.
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 25_000, abs(location.timestamp.timeIntervalSinceNow) < 15 * 60,
              let point = try? WeatherCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) else { return }
        Task { @MainActor [weak self] in self?.received(point) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.isEnabled else { return }
            if (error as? CLError)?.code == .denied { self.updateAuthorization(allowPrompt: false) }
            else if self.coordinate == nil { self.status = "定位暂不可用"; self.error = "请检查 Mac 的定位服务和网络连接。" }
        }
    }

    private func received(_ point: WeatherCoordinate) {
        guard isEnabled else { return }
        guard hasLocationAccess else { updateAuthorization(allowPrompt: false); return }
        locationTimeout?.cancel(); locationTimeout = nil
        if coordinate != point {
            coordinate = point; snapshot = nil; city = "本地"
            cityTask?.cancel(); geocoder.cancelGeocode()
            cityTask = Task { [weak self] in
                guard let self else { return }
                let cityLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
                if let mark = try? await geocoder.reverseGeocodeLocation(cityLocation, preferredLocale: Locale(identifier: "zh_CN")).first,
                   !Task.isCancelled, coordinate == point, isEnabled {
                    city = mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea ?? "本地"
                }
            }
            fetch(point, force: true)
        } else { fetch(point, force: false) }
    }

    private func fetch(_ point: WeatherCoordinate, force: Bool) {
        guard isEnabled, hasLocationAccess else { updateAuthorization(allowPrompt: false); return }
        if !force {
            if isLoading { return }
            if let snapshot, snapshot.coordinate == point, Date().timeIntervalSince(snapshot.fetchedAt) < 15 * 60 { return }
        }
        forecastTask?.cancel()
        let id = UUID(); generation = id
        isLoading = true; error = nil; status = "正在更新天气…"
        forecastTask = Task { [weak self, client] in
            do {
                let value = try await client.current(at: point)
                guard !Task.isCancelled, let self, self.generation == id, self.isEnabled, self.coordinate == point else { return }
                self.snapshot = value; self.isLoading = false
                self.status = value.isFresh(at: Date()) ? "天气已更新" : "天气暂不可用"
                self.logger.notice("Weather update complete; fresh: \(value.isFresh(at: Date()), privacy: .public)")
            } catch {
                guard !Task.isCancelled, let self, self.generation == id, self.isEnabled else { return }
                self.isLoading = false; self.status = "天气暂不可用"
                self.error = "天气服务暂时无法连接，稍后会自动重试。"
                self.logger.notice("Weather update unavailable")
            }
        }
    }

    private var hasLocationAccess: Bool {
        guard let manager, CLLocationManager.locationServicesEnabled() else { return false }
        return manager.authorizationStatus == .authorizedAlways
    }
}
