import Foundation

/// Local civil time drives the sky, independently of the pomodoro's countdown.
/// No location or network is needed: daylight spans 06:00–18:00 on this Mac.
public struct FocusSky: Sendable {
    public let localHour: Double
    public let isDay: Bool
    public let journey: Double
    public let daylight: Double
    public let twilight: Double

    public init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            + Double(parts.second ?? 0) / 3600 + Double(parts.nanosecond ?? 0) / 3_600_000_000_000
        localHour = hour
        isDay = hour >= 6 && hour < 18
        journey = isDay ? (hour - 6) / 12 : (hour < 6 ? hour + 6 : hour - 18) / 12
        daylight = Self.smoothstep((hour - 5.5) / 1.5) * (1 - Self.smoothstep((hour - 17) / 1.5))
        twilight = max(0, max(1 - abs(hour - 6) / 2, 1 - abs(hour - 18) / 2))
    }

    /// Fixed logical points: window resizing changes the view, not the objects.
    public var bodyDiameter: Double { isDay ? 264 : 310 }
    public func bodyPosition(width: Double, height: Double, diameter: Double? = nil) -> (x: Double, y: Double) {
        let radius = (diameter ?? bodyDiameter) / 2
        return (x: -radius + journey * (width + 2 * radius),
                y: 64 + (max(180, height * 0.54) - 64) * (1 - sin(.pi * journey)))
    }
    public static func cloudCount(width: Double, height: Double) -> Int {
        min(30, max(8, Int(ceil(max(0, width * height) / 95_000))))
    }
    public static func starCount(width: Double, height: Double) -> Int {
        min(800, max(180, Int(ceil(max(0, width * height) / 3_500))))
    }
    public static func cloudWidth(layer: Int) -> Double { [210.0, 165, 240, 190, 150, 220][abs(layer) % 6] }
    /// Bodies fade in at the card edge; the sun and moon never pop into its centre.
    public var bodyOpacity: Double {
        Self.smoothstep(min(journey, 1 - journey) / 0.025)
    }
    public static let cloudSpeeds = [4.5, 8.0, 13.0, 6.0]
    public static let starPeriod: TimeInterval = 420
    public static func cloudX(time: TimeInterval, width: Double, cloudWidth: Double, layer: Int) -> Double {
        let speed = cloudSpeeds[abs(layer) % cloudSpeeds.count]
        let span = width + 2 * cloudWidth
        let phase = time * speed + Double(layer) * 217.3
        return ((phase.truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span)) - cloudWidth
    }
    public static func starAngle(time: TimeInterval) -> Double {
        time.truncatingRemainder(dividingBy: starPeriod) / starPeriod * 2 * .pi
    }
    private static func smoothstep(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
    }
}
