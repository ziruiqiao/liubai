import Foundation
import LiuBaiCore

enum WeatherChecks {
    static func run() async throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw WeatherCheckFailure(message: message) }
            count += 1
        }
        let coordinate = try WeatherCoordinate(latitude: 39.904211, longitude: 116.407395)
        try check(coordinate.latitude == 39.9 && coordinate.longitude == 116.4, "Weather coordinates must be city-level before they leave the location callback")
        for (lat, lon) in [(91.0, 0.0), (0, 181), (.nan, 0), (0, .infinity)] {
            var refused = false
            do { _ = try WeatherCoordinate(latitude: lat, longitude: lon) } catch { refused = true }
            try check(refused, "Invalid system coordinates must never produce weather requests")
        }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func fixture(_ code: Int, precipitation: Double = 0, snow: Double = 0, wind: Double = 8) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["current": [
                "time": now.timeIntervalSince1970, "temperature_2m": 18.4, "weather_code": code,
                "wind_speed_10m": wind, "wind_direction_10m": 90, "precipitation": precipitation,
                "snowfall": snow, "cloud_cover": 60
            ]])
        }
        for code in [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 97, 99] {
            let value = try WeatherSnapshot.decode(fixture(code), coordinate: coordinate, now: now)
            try check(value.visuals.precipitation == .rain, "WMO rain, freezing rain, and storms must use gentle rain rather than flashing effects")
        }
        for code in [71, 73, 75, 77, 85, 86] {
            let value = try WeatherSnapshot.decode(fixture(code, snow: 1), coordinate: coordinate, now: now)
            try check(value.visuals.precipitation == .snow, "WMO snow and snow showers must map to snowfall")
        }
        let clear = try WeatherSnapshot.decode(fixture(0), coordinate: coordinate, now: now)
        try check(clear.visuals.precipitation == .none && clear.description == "晴", "Dry clear weather must not invent precipitation")
        for code in [65, 67, 82, 95, 96, 97, 99] {
            let value = try WeatherSnapshot.decode(fixture(code), coordinate: coordinate, now: now)
            try check(value.visuals.isHeavy && value.visuals.precipitation == .rain,
                      "Heavy rain and storms must use the distinct dense-rain background")
        }
        for code in [75, 86] {
            let value = try WeatherSnapshot.decode(fixture(code), coordinate: coordinate, now: now)
            try check(value.visuals.isHeavy && value.visuals.precipitation == .snow,
                      "Heavy snowfall and snow showers must use the distinct dense-snow background")
        }
        let lightRain = try WeatherSnapshot.decode(fixture(61), coordinate: coordinate, now: now)
        let lightSnow = try WeatherSnapshot.decode(fixture(71), coordinate: coordinate, now: now)
        try check(!lightRain.visuals.isHeavy && !lightSnow.visuals.isHeavy,
                  "Ordinary rain and snow must retain the calmer animation")
        let cloudy = try WeatherSnapshot.decode(fixture(2), coordinate: coordinate, now: now)
        try check(cloudy.visuals.precipitation == .none && cloudy.visuals.cloudCover >= 0.7,
                  "Partly cloudy weather must add cloud layers without inventing rain")
        try check(SkyWeather.heavyRainPreview.particleCountPerMillionPoints > SkyWeather.rainPreview.particleCountPerMillionPoints * 3
                  && SkyWeather.heavySnowPreview.particleCountPerMillionPoints > SkyWeather.snowPreview.particleCountPerMillionPoints * 3,
                  "Heavy-weather previews must be visibly denser than ordinary rain and snow")
        let extreme = try WeatherSnapshot.decode(fixture(65, precipitation: 100, wind: 180), coordinate: coordinate, now: now)
        try check(extreme.description == "大雨" && extreme.visuals.intensity <= 0.7 && extreme.visuals.cloudSpeed <= 2.2,
                  "The text must retain actual weather severity while visual intensity stays calm")
        try check(extreme.visuals.horizontalWind < 0, "An easterly wind must move the cloud layer towards the west")
        try check(clear.isFresh(at: now.addingTimeInterval(600)) && !clear.isFresh(at: now.addingTimeInterval(46 * 60)),
                  "Outdated cached weather must stop driving the sky")
        try check(!clear.isFresh(at: now.addingTimeInterval(-3600)), "Future timestamps after a clock change must not masquerade as current weather")
        let invalidVisuals = SkyWeather(precipitation: .rain, intensity: .infinity, cloudCover: -2, windKmh: .nan, windDirection: .nan)
        try check(invalidVisuals.intensity == 0 && invalidVisuals.windKmh == 0 && invalidVisuals.cloudCover == 0,
                  "Malformed input must not create unbounded motion or opacity")

        var data = AppData()
        data.weatherEnabled = false
        let bytes = try FileStore.encode(data)
        let decoded = try FileStore.decode(bytes)
        try check(!decoded.usesWeather, "Disabling weather must persist across launches")
        var older = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        older.removeValue(forKey: "weatherEnabled")
        let legacy = try FileStore.decode(JSONSerialization.data(withJSONObject: older))
        try check(legacy.usesWeather && legacy.tracks.isEmpty, "The optional weather preference must preserve compatibility with existing documents")
        let json = String(decoding: bytes, as: UTF8.self)
        try check(!json.contains("latitude") && !json.contains("longitude") && !json.contains("39.9"), "App backups must contain neither system coordinates nor location history")

        let transport = FixtureWeatherTransport(bytes: try fixture(61, precipitation: 0.4))
        let client = WeatherClient(transport: transport)
        let result = try await client.current(at: coordinate)
        let requests = await transport.recorded()
        let request = requests[0]
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        try check(result.visuals.precipitation == .rain && requests.count == 1 && request.httpMethod == "GET", "The client must read current weather without modifying remote data")
        try check(request.url?.host == "api.open-meteo.com" && request.url?.scheme == "https"
                  && request.value(forHTTPHeaderField: "Cookie") == nil && request.value(forHTTPHeaderField: "Authorization") == nil,
                  "Weather requests must never receive Bilibili account credentials")
        try check(query.first(where: { $0.name == "latitude" })?.value == "39.9"
                  && query.first(where: { $0.name == "longitude" })?.value == "116.4", "Only coarse coordinates may be sent to the weather provider")
        try check(query.first(where: { $0.name == "timeformat" })?.value == "unixtime"
                  && query.first(where: { $0.name == "wind_speed_unit" })?.value == "kmh", "Weather timestamps and wind units must not depend on the Mac's locale")
        var missingRejected = false
        do { _ = try WeatherSnapshot.decode(Data("{\"current\":{}}".utf8), coordinate: coordinate) } catch { missingRejected = true }
        try check(missingRejected, "Missing weather data must fail rather than silently showing a sunny forecast")
        return count
    }
}

private struct WeatherCheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private actor FixtureWeatherTransport: WeatherTransport {
    let bytes: Data
    private var requests: [URLRequest] = []
    init(bytes: Data) { self.bytes = bytes }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func recorded() -> [URLRequest] { requests }
}
