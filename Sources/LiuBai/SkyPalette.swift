import AppKit
import LiuBaiCore
import SwiftUI

// Sky artwork is independent of the interface theme.
enum SkyPalette {
    static let bodyOutline = Color.white
    static let sunHalo = Color(hex: 0xFFE3AA)
    static let moonHalo = Color(hex: 0xDDE9E9)
    static let sunTop = Color(hex: 0xFFF3BC)
    static let sunBottom = Color(hex: 0xEAB86F)
    static let moonTop = Color(hex: 0xFCF6D8)
    static let moonBottom = Color(hex: 0xC9D8CD)
    static let moonCrater = Color(hex: 0x8EAAA9)
    static let cloud = Color.white
    static let cloudShade = Color(hex: 0xF2FAFF)
    static let star = Color(hex: 0xF4EEDC)
    static let rain = Color(hex: 0xE9F7FF)
    static let snow = Color.white
    static let wind = Color.white
    // Opaque paint for destination-out, independent of the visible theme.
    static let mask = Color.black
}

struct SkyColors {
    let top: Color
    let middle: Color
    let bottom: Color
    let landscapeFar: Color
    let landscapeNear: Color

    init(_ sky: FocusSky) {
        // Keep sky colours in separate vertical bands. Mixing a blue sky with
        // orange over the whole frame had cancelled their chroma into grey.
        top = Self.skyColor(hour: sky.localHour, channel: \.top)
        middle = Self.skyColor(hour: sky.localHour, channel: \.middle)
        bottom = Self.skyColor(hour: sky.localHour, channel: \.bottom)
        landscapeFar = Self.skyColor(hour: sky.localHour, channel: \.far)
        landscapeNear = Self.skyColor(hour: sky.localHour, channel: \.near)

    }
    private struct SkyStop {
        let hour: Double
        let top: UInt32
        let middle: UInt32
        let bottom: UInt32
        let far: UInt32
        let near: UInt32
    }
    private static let skyStops: [SkyStop] = [
        .init(hour: 0, top: 0x102655, middle: 0x244782, bottom: 0x426CB0, far: 0x305399, near: 0x23417F),
        .init(hour: 4, top: 0x172D69, middle: 0x494DA0, bottom: 0xB591DC, far: 0x6C72BF, near: 0x515BA6),
        .init(hour: 5, top: 0x426CC3, middle: 0xBAAAEF, bottom: 0xFFC294, far: 0xB19BD9, near: 0x8A8BD1),
        .init(hour: 6.25, top: 0x58B5F5, middle: 0xF9C1E6, bottom: 0xFFD59A, far: 0xF3B7BD, near: 0xDA94AD),
        .init(hour: 7, top: 0x46AEF8, middle: 0x9DD8FF, bottom: 0xF4C8F4, far: 0xC8BCED, near: 0xAAA6E5),
        .init(hour: 8, top: 0x2CA5F5, middle: 0x75CFFF, bottom: 0xC8EFFF, far: 0x74C9DF, near: 0x43B6D2),
        .init(hour: 12, top: 0x239FF5, middle: 0x68CAFF, bottom: 0xC1ECFF, far: 0x6AC7E1, near: 0x38AFD0),
        .init(hour: 15, top: 0x36A5F5, middle: 0x83D1FF, bottom: 0xCDEEFF, far: 0x80CCDF, near: 0x52B7D3),
        .init(hour: 16, top: 0x659DF1, middle: 0xB9CEFF, bottom: 0xFFE2D0, far: 0xC4B8E9, near: 0xA29EDC),
        .init(hour: 17.5, top: 0x7B8BF0, middle: 0xF2B6DE, bottom: 0xFFC184, far: 0xD098D4, near: 0xB282CB),
        .init(hour: 18, top: 0x586FD6, middle: 0xD599DF, bottom: 0xFFB97A, far: 0xB989CE, near: 0x966CC0),
        .init(hour: 19, top: 0x304AA3, middle: 0x9477D1, bottom: 0xEBA7C3, far: 0x8B79C3, near: 0x6A65AF),
        .init(hour: 21, top: 0x132D64, middle: 0x2B4D89, bottom: 0x4A70B4, far: 0x37599B, near: 0x294783),
        .init(hour: 24, top: 0x102655, middle: 0x244782, bottom: 0x426CB0, far: 0x305399, near: 0x23417F)
    ]
    private static func skyColor(hour: Double, channel: KeyPath<SkyStop, UInt32>) -> Color {
        let upper = skyStops.firstIndex(where: { $0.hour > hour }) ?? (skyStops.count - 1)
        let left = skyStops[max(0, upper - 1)]
        let right = skyStops[upper]
        let t = min(1, max(0, (hour - left.hour) / max(0.001, right.hour - left.hour)))
        let smooth = t * t * (3 - 2 * t)
        let a = NSColor(Color(hex: left[keyPath: channel])).usingColorSpace(.sRGB)!
        let b = NSColor(Color(hex: right[keyPath: channel])).usingColorSpace(.sRGB)!
        var hueDelta = b.hueComponent - a.hueComponent
        if hueDelta > 0.5 { hueDelta -= 1 }
        if hueDelta < -0.5 { hueDelta += 1 }
        let hue = (a.hueComponent + hueDelta * smooth + 1).truncatingRemainder(dividingBy: 1)
        // Preserve chroma while time advances, instead of averaging distinct
        // sky hues through a low-saturation RGB midpoint.
        return Color(hue: hue, saturation: a.saturationComponent * (1 - smooth) + b.saturationComponent * smooth,
                     brightness: a.brightnessComponent * (1 - smooth) + b.brightnessComponent * smooth)
    }
    static func mix(_ from: UInt32, _ to: UInt32, _ t: Double) -> Color {
        mix(Color(hex: from), to, t)
    }
    static func mix(_ from: Color, _ to: UInt32, _ t: Double) -> Color {
        let first = NSColor(from).usingColorSpace(.sRGB)!
        let second = NSColor(Color(hex: to)).usingColorSpace(.sRGB)!
        let t = min(1, max(0, t))
        return Color(.sRGB, red: first.redComponent * (1 - t) + second.redComponent * t,
                     green: first.greenComponent * (1 - t) + second.greenComponent * t,
                     blue: first.blueComponent * (1 - t) + second.blueComponent * t, opacity: 1)
    }
}

