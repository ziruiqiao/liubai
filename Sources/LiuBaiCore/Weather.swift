import Foundation

/// Quantize immediately, before reverse geocoding, storage, or HTTP requests.
/// A tenth of a degree is city-level; raw system coordinates are not retained.
public struct WeatherCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw WeatherError.invalidResponse
        }
        self.latitude = (latitude * 10).rounded() / 10
        self.longitude = (longitude * 10).rounded() / 10
    }
}

public enum SkyPrecipitation: String, CaseIterable, Sendable { case none, rain, snow }

public struct SkyWeather: Equatable, Sendable {
    public var precipitation: SkyPrecipitation
    public var intensity: Double
    public var cloudCover: Double
    public var windKmh: Double
    public var windDirection: Double
    public var isHeavy: Bool
    public static let clear = SkyWeather(precipitation: .none, intensity: 0, cloudCover: 0, windKmh: 0, windDirection: 270)

    public init(precipitation: SkyPrecipitation, intensity: Double, cloudCover: Double, windKmh: Double, windDirection: Double, isHeavy: Bool = false) {
        self.precipitation = precipitation
        self.intensity = intensity.isFinite ? min(0.7, max(0, intensity)) : 0
        self.cloudCover = cloudCover.isFinite ? min(1, max(0, cloudCover)) : 0
        self.windKmh = windKmh.isFinite ? min(200, max(0, windKmh)) : 0
        self.windDirection = windDirection.isFinite ? windDirection.truncatingRemainder(dividingBy: 360) : 270
        self.isHeavy = isHeavy && precipitation != .none
    }
    public var windStrength: Double { min(0.7, max(0, (windKmh - 12) / 50)) }
    public var cloudSpeed: Double { 1 + min(1.2, windKmh / 35) }
    public var signedCloudSpeed: Double { cloudSpeed * (horizontalWind < -0.15 ? -1 : 1) }
    /// Meteorological directions describe where wind comes from.
    public var horizontalWind: Double { -sin(windDirection * .pi / 180) }
    public var particleCountPerMillionPoints: Double { precipitation == .snow ? (isHeavy ? 330 : 90) : (isHeavy ? 520 : 115) }
    public static let cloudyPreview = SkyWeather(precipitation: .none, intensity: 0, cloudCover: 0.92, windKmh: 14, windDirection: 270)
    public static let rainPreview = SkyWeather(precipitation: .rain, intensity: 0.55, cloudCover: 0.65, windKmh: 12, windDirection: 270)
    public static let snowPreview = SkyWeather(precipitation: .snow, intensity: 0.55, cloudCover: 0.60, windKmh: 7, windDirection: 270)
    public static let heavyRainPreview = SkyWeather(precipitation: .rain, intensity: 0.7, cloudCover: 0.95, windKmh: 38, windDirection: 270, isHeavy: true)
    public static let heavySnowPreview = SkyWeather(precipitation: .snow, intensity: 0.7, cloudCover: 0.95, windKmh: 30, windDirection: 270, isHeavy: true)
    public static let windPreview = SkyWeather(precipitation: .none, intensity: 0, cloudCover: 0.30, windKmh: 35, windDirection: 270)
}

public struct WeatherSnapshot: Sendable {
    public let coordinate: WeatherCoordinate
    public let code: Int
    public let temperature: Double
    public let windKmh: Double
    public let windDirection: Double
    public let precipitationMM: Double
    public let snowfallCM: Double
    public let cloudCover: Double
    public let modelTime: Date
    public let fetchedAt: Date

    public var description: String {
        switch code {
        case 0: return "晴"
        case 1: return "少云"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "细雨"
        case 56, 57, 66, 67: return "冻雨"
        case 61, 80: return "小雨"
        case 63, 81: return "中雨"
        case 65, 82: return "大雨"
        case 71, 77, 85: return "小雪"
        case 73: return "中雪"
        case 75, 86: return "大雪"
        case 95...99: return "雷雨"
        default: return "天气"
        }
    }
    public var icon: String {
        switch visuals.precipitation {
        case .rain: return "cloud.rain"
        case .snow: return "cloud.snow"
        case .none:
            if windKmh >= 25 { return "wind" }
            if code == 45 || code == 48 { return "cloud.fog" }
            return code == 0 ? "sun.max" : "cloud.sun"
        }
    }
    public var visuals: SkyWeather {
        let kind: SkyPrecipitation
        switch code {
        case 71, 73, 75, 77, 85, 86: kind = .snow
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95...99: kind = .rain
        default: kind = snowfallCM > 0 ? .snow : (precipitationMM > 0 ? .rain : .none)
        }
        let amount = kind == .snow ? snowfallCM : precipitationMM
        let heavy = [65, 67, 75, 82, 86, 95, 96, 97, 99].contains(code)
        let minimumCover = heavy ? 0.90 : (code == 3 ? 0.95 : (code == 2 ? 0.70 : 0))
        return SkyWeather(precipitation: kind, intensity: kind == .none ? 0 : (heavy ? 0.7 : 0.34 + min(0.36, amount * 0.12)),
                          cloudCover: max(minimumCover, cloudCover / 100), windKmh: windKmh, windDirection: windDirection, isHeavy: heavy)
    }
    public func isFresh(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) < 45 * 60 && date.timeIntervalSince(modelTime) < 2 * 3600
            && modelTime.timeIntervalSince(date) < 15 * 60
    }

    public static func decode(_ bytes: Data, coordinate: WeatherCoordinate, now: Date = Date()) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        let c = response.current
        guard c.temperature_2m.isFinite, c.wind_speed_10m.isFinite, c.wind_speed_10m >= 0,
              c.precipitation >= 0, c.snowfall >= 0, (0...100).contains(c.cloud_cover) else { throw WeatherError.invalidResponse }
        return WeatherSnapshot(coordinate: coordinate, code: c.weather_code, temperature: c.temperature_2m,
                               windKmh: c.wind_speed_10m, windDirection: c.wind_direction_10m,
                               precipitationMM: c.precipitation, snowfallCM: c.snowfall, cloudCover: c.cloud_cover,
                               modelTime: Date(timeIntervalSince1970: c.time), fetchedAt: now)
    }
    private struct Response: Decodable {
        let current: Current
        struct Current: Decodable {
            let time: Double
            let weather_code: Int
            let temperature_2m: Double
            let wind_speed_10m: Double
            let wind_direction_10m: Double
            let precipitation: Double
            let snowfall: Double
            let cloud_cover: Double
        }
    }
}

public enum WeatherError: LocalizedError {
    case invalidResponse, unavailable
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "天气数据暂不可用。"
        case .unavailable: return "天气服务暂时无法连接。"
        }
    }
}

public protocol WeatherTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class WeatherNetworkTransport: WeatherTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel() }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 256_000 else {
            throw WeatherError.unavailable
        }
        return (data, response)
    }
}

public actor WeatherClient {
    private let transport: any WeatherTransport
    public init(transport: any WeatherTransport = WeatherNetworkTransport()) { self.transport = transport }
    public func current(at coordinate: WeatherCoordinate) async throws -> WeatherSnapshot {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation,snowfall,cloud_cover"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"), URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        var request = URLRequest(url: url.url!)
        request.httpMethod = "GET"
        let (bytes, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw WeatherError.unavailable }
        return try WeatherSnapshot.decode(bytes, coordinate: coordinate)
    }
}
