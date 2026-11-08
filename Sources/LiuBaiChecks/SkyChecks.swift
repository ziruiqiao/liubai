import Foundation
import LiuBaiCore

enum SkyChecks {
    static func run() throws -> Int {
        var count = 0
        func check(_ result: Bool, _ message: String) throws {
            guard result else { throw NSError(domain: "SkyChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            count += 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: hour, minute: minute, second: second))!
        }
        let noon = FocusSky(date: date(12), calendar: calendar)
        let midnight = FocusSky(date: date(0), calendar: calendar)
        try check(noon.isDay && abs(noon.journey - 0.5) < 0.00001 && noon.daylight == 1, "Local noon must show the sun at the top of its journey")
        try check(!midnight.isDay && abs(midnight.journey - 0.5) < 0.00001 && midnight.daylight == 0, "Local midnight must show the moon and night sky")
        try check(!FocusSky(date: date(5, 59, 59), calendar: calendar).isDay && FocusSky(date: date(6), calendar: calendar).isDay,
                  "Daylight must begin at local 06:00")
        try check(FocusSky(date: date(17, 59, 59), calendar: calendar).isDay && !FocusSky(date: date(18), calendar: calendar).isDay,
                  "The moon must take over at local 18:00")
        let beforeMidnight = FocusSky(date: date(23, 59, 59), calendar: calendar)
        let nextMidnight = FocusSky(date: date(23, 59, 59).addingTimeInterval(1), calendar: calendar)
        try check(nextMidnight.journey > beforeMidnight.journey && nextMidnight.journey - beforeMidnight.journey < 0.0001,
                  "The moon must cross midnight without restarting its path")
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        try check(!FocusSky(date: date(12), calendar: utc).isDay, "The same instant must follow the computer's chosen time zone rather than a hardcoded zone")
        let now = Date()
        let local = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second], from: now)
        let expected = Double(local.hour!) + Double(local.minute!) / 60 + Double(local.second!) / 3600
        try check(abs(FocusSky(date: now).localHour - expected) < 0.001, "The default sky must use this Mac's current local time")
        for (width, height) in [(450.0, 490.0), (570, 490), (1000, 490)] {
            for sky in [noon, midnight] {
                let diameter = sky.bodyDiameter
                let area = Double.pi * diameter * diameter / 4
                try check(area >= width * height / 16, "Celestial bodies must be large enough for the card, even before edge clipping")
                let position = sky.bodyPosition(width: width, height: height)
                try check(abs(position.x - width / 2) < 0.001, "The body must move across the card instead of orbiting the timer face")
            }
        }
        let sunSpeed = (570 + noon.bodyDiameter) / (12 * 3600)
        try check(FocusSky.cloudSpeeds.min()! > sunSpeed * 100, "Clouds must be visibly much faster than the real-time sun")
        for layer in 0..<4 {
            let x = FocusSky.cloudX(time: -123456.75, width: 570, cloudWidth: 200, layer: layer)
            try check(x >= -200 && x < 770, "Cloud wrapping must stay outside the horizontal card edges, including old timestamps")
        }
        let angle = FocusSky.starAngle(time: 12345)
        let fullTurn = FocusSky.starAngle(time: 12345 + FocusSky.starPeriod)
        try check(abs(sin(angle) - sin(fullTurn)) < 0.000001 && abs(cos(angle) - cos(fullTurn)) < 0.000001,
                  "Stars must complete a circular journey around a fixed pole")
        let dawnBefore = FocusSky(date: date(5, 59, 59), calendar: calendar)
        let dawnAfter = FocusSky(date: date(6, 0, 1), calendar: calendar)
        try check(abs(dawnAfter.daylight - dawnBefore.daylight) < 0.002, "Dawn colours must blend across the day/night boundary")
        try check(FocusSky(date: date(6), calendar: calendar).bodyOpacity == 0 && FocusSky(date: date(18), calendar: calendar).bodyOpacity == 0,
                  "Celestial bodies must exchange at the clipped edges without a central flash")
        let small = noon.bodyPosition(width: 900, height: 700)
        let large = noon.bodyPosition(width: 1600, height: 1100)
        try check(noon.bodyDiameter == 264 && midnight.bodyDiameter == 310 && small.y == large.y,
                  "Resizing must keep celestial-body sizes and the noon horizon fixed in logical points")
        try check(FocusSky.cloudCount(width: 1600, height: 1100) > FocusSky.cloudCount(width: 900, height: 700)
                  && FocusSky.starCount(width: 1600, height: 1100) > FocusSky.starCount(width: 900, height: 700),
                  "Larger focus spaces must add clouds and stars instead of stretching them")
        return count
    }
}
