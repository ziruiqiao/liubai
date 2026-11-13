import AppKit
import LiuBaiCore
import SwiftUI

/// Absolute time also drives the decorative motion, so reopening the window
/// resumes the sky at the right position instead of restarting an animation.
struct FocusSkyBackground: View {
    var dateOverride: Date? = nil
    var motionOverride: Date? = nil
    var motionRate: Double = 1
    var weather: SkyWeather = .clear
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = true
    @State private var cloudMotionOffset: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion || motionOverride != nil ? 60 : 1.0 / 15, paused: !windowVisible)) { timeline in
            FocusSkyScene(date: dateOverride ?? timeline.date,
                          motionDate: motionOverride ?? (reduceMotion ? .referenceDate : Date(timeIntervalSinceReferenceDate: timeline.date.timeIntervalSinceReferenceDate * motionRate)), weather: weather, compact: compact, cloudMotionOffset: cloudMotionOffset)
        }
        .onChange(of: weather) { old, new in
            let time = motionOverride?.timeIntervalSinceReferenceDate ?? (reduceMotion ? 0 : Date().timeIntervalSinceReferenceDate * motionRate)
            // Preserve cloud positions when fresh weather changes their speed.
            cloudMotionOffset += time * (old.signedCloudSpeed - new.signedCloudSpeed)
        }
        .background(SkyWindowVisibility { windowVisible = $0 })
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct FocusSkyScene: View {
    let date: Date
    let motionDate: Date
    var weather: SkyWeather = .clear
    var compact = false
    var cloudMotionOffset: Double = 0
    var body: some View {
        let sky = FocusSky(date: date)
        let colors = SkyColors(sky)
        Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: false) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(Gradient(stops: [
                .init(color: colors.top, location: 0),
                .init(color: colors.middle, location: 0.54),
                .init(color: colors.bottom, location: 1)
            ]),
                                                          startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            drawStars(context, size: size, sky: sky)
            drawClouds(context, size: size, sky: sky, foreground: false)
            drawBody(context, size: size, sky: sky)
            drawClouds(context, size: size, sky: sky, foreground: true)
            drawWeather(context, size: size, sky: sky)
            drawLandscape(context, size: size, sky: sky)
        }.accessibilityHidden(true)
    }

    private func drawBody(_ context: GraphicsContext, size: CGSize, sky: FocusSky) {
        let diameter = compact ? 186 : sky.bodyDiameter
        let centre = sky.bodyPosition(width: size.width, height: size.height, diameter: diameter)
        let point = CGPoint(x: centre.x, y: centre.y)
        let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
        var body = context
        body.opacity = sky.bodyOpacity
        let halo = rect.insetBy(dx: -diameter * 0.38, dy: -diameter * 0.38)
        body.fill(Path(ellipseIn: halo), with: .radialGradient(Gradient(colors: [
            (sky.isDay ? SkyPalette.sunHalo : SkyPalette.moonHalo).opacity(sky.isDay ? 0.44 : 0.15), .clear
        ]), center: point, startRadius: diameter * 0.22, endRadius: diameter * 0.88))
        if sky.isDay {
            body.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [SkyPalette.sunTop, SkyPalette.sunBottom]),
                                                                 startPoint: CGPoint(x: point.x, y: rect.minY), endPoint: CGPoint(x: point.x, y: rect.maxY)))
            body.stroke(Path(ellipseIn: rect.insetBy(dx: 7, dy: 7)), with: .color(SkyPalette.bodyOutline.opacity(0.13)), lineWidth: 1)
        } else {
            body.drawLayer { moon in
                moon.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [SkyPalette.moonTop, SkyPalette.moonBottom]),
                                                                     startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                for (x, y, radius) in [(0.23, 0.44, 0.065), (0.32, 0.74, 0.045), (0.17, 0.59, 0.026)] {
                    let mark = CGRect(x: rect.minX + diameter * x, y: rect.minY + diameter * y, width: diameter * radius, height: diameter * radius)
                    moon.fill(Path(ellipseIn: mark), with: .color(SkyPalette.moonCrater.opacity(0.17)))
                }
                // Subtract in an isolated layer so the dark side has no faint
                // circular seam and does not erase the sky or stars beneath it.
                moon.blendMode = .destinationOut
                moon.fill(Path(ellipseIn: rect.offsetBy(dx: diameter * 0.45, dy: -diameter * 0.10)), with: .color(SkyPalette.mask))
            }
        }
    }

    private func drawClouds(_ context: GraphicsContext, size: CGSize, sky: FocusSky, foreground: Bool) {
        let cloudLight = max(sky.daylight, weather.cloudCover * 0.18)
        guard cloudLight > 0.002 else { return }
        let time = motionDate.timeIntervalSinceReferenceDate * weather.signedCloudSpeed + cloudMotionOffset
        let count = FocusSky.cloudCount(width: size.width, height: size.height) + Int(weather.cloudCover * 10)
        for index in 0..<count where (index % 3 != 0) == foreground {
            let width = FocusSky.cloudWidth(layer: index) * (compact ? 0.6 : 1)
            let height = width * 0.22
            let x = FocusSky.cloudX(time: time, width: size.width, cloudWidth: width, layer: index)
            let y = size.height * (0.10 + (Double(index) * 0.193).truncatingRemainder(dividingBy: 0.72))
            var cloud = context
            cloud.translateBy(x: x, y: y)
            cloud.opacity = cloudLight * (foreground ? 0.72 : 0.48)
            if !foreground { cloud.addFilter(.blur(radius: 0.8)) }
            cloud.fill(Self.cloudPath(width: width, height: height), with: .linearGradient(Gradient(colors: [SkyPalette.cloud, SkyPalette.cloudShade.opacity(0.78)]),
                                                                                          startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))
        }
    }
    private static func cloudPath(width w: Double, height h: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * 0.76))
        path.addCurve(to: CGPoint(x: w * 0.18, y: h * 0.40), control1: CGPoint(x: -w * 0.02, y: h * 0.47), control2: CGPoint(x: w * 0.08, y: h * 0.32))
        path.addCurve(to: CGPoint(x: w * 0.53, y: h * 0.29), control1: CGPoint(x: w * 0.21, y: -h * 0.14), control2: CGPoint(x: w * 0.47, y: -h * 0.17))
        path.addCurve(to: CGPoint(x: w * 0.77, y: h * 0.46), control1: CGPoint(x: w * 0.66, y: h * 0.12), control2: CGPoint(x: w * 0.77, y: h * 0.22))
        path.addCurve(to: CGPoint(x: w, y: h * 0.75), control1: CGPoint(x: w * 0.92, y: h * 0.29), control2: CGPoint(x: w * 1.05, y: h * 0.50))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.76), control1: CGPoint(x: w * 1.01, y: h * 1.02), control2: CGPoint(x: w * 0.04, y: h * 1.02))
        path.closeSubpath()
        return path
    }

    private struct Star {
        let radius: Double
        let angle: Double
        let size: Double
        let opacity: Double
    }
    private static let stars: [Star] = {
        var seed: UInt32 = 37
        func next() -> Double {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            return Double(seed) / Double(UInt32.max)
        }
        return (0..<800).map { _ in Star(radius: 0.09 + 0.88 * sqrt(next()), angle: next() * 2 * .pi,
                                        size: 0.65 + next() * 0.95, opacity: 0.32 + next() * 0.48) }
    }()
    private func drawStars(_ context: GraphicsContext, size: CGSize, sky: FocusSky) {
        let strength = pow(1 - sky.daylight, 1.6) * (1 - weather.cloudCover * 0.28)
        guard strength > 0.002 else { return }
        let pole = CGPoint(x: size.width * 0.80, y: size.height * 0.21)
        let rotation = FocusSky.starAngle(time: motionDate.timeIntervalSinceReferenceDate)
        let scale = max(size.width, size.height)
        for (index, star) in Self.stars.prefix(FocusSky.starCount(width: size.width, height: size.height)).enumerated() {
            let angle = star.angle + rotation
            let point = CGPoint(x: pole.x + cos(angle) * star.radius * scale,
                                y: pole.y + sin(angle) * star.radius * scale)
            let radius = star.size
            let color = SkyPalette.star.opacity(star.opacity * strength)
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
            if index % 9 == 0 { cross(context, point: point, length: radius * 3.1, color: color.opacity(0.75)) }
        }
        cross(context, point: pole, length: 4, color: SkyPalette.star.opacity(strength * 0.7))
    }
    private func cross(_ context: GraphicsContext, point: CGPoint, length: Double, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: point.x - length, y: point.y)); path.addLine(to: CGPoint(x: point.x + length, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - length)); path.addLine(to: CGPoint(x: point.x, y: point.y + length))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
    }
    private func drawLandscape(_ context: GraphicsContext, size: CGSize, sky: FocusSky) {
        let colors = SkyColors(sky)
        for layer in 0..<2 {
            let y = size.height * (layer == 0 ? 0.86 : 0.93)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addCurve(to: CGPoint(x: size.width, y: y + size.height * 0.025),
                          control1: CGPoint(x: size.width * 0.32, y: y - size.height * 0.12),
                          control2: CGPoint(x: size.width * 0.65, y: y + size.height * 0.08))
            path.addLine(to: CGPoint(x: size.width, y: size.height)); path.addLine(to: CGPoint(x: 0, y: size.height)); path.closeSubpath()
            let color = layer == 0 ? colors.landscapeFar : colors.landscapeNear
            context.fill(path, with: .color(color.opacity(layer == 0 ? 0.30 : 0.27)))
        }
    }

    private struct WeatherParticle {
        let x: Double, y: Double, speed: Double, size: Double
    }
    private static let weatherParticles: [WeatherParticle] = {
        var seed: UInt32 = 719
        func unit() -> Double {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            return Double(seed) / Double(UInt32.max)
        }
        return (0..<420).map { _ in WeatherParticle(x: unit(), y: unit(), speed: unit(), size: unit()) }
    }()

    private func drawWeather(_ context: GraphicsContext, size: CGSize, sky: FocusSky) {
        let time = motionDate.timeIntervalSinceReferenceDate
        let strength = weather.windStrength
        if strength > 0.01 {
            for index in 0..<5 {
                let span = size.width + 220
                let phase = time * (18 + strength * 20) * (weather.horizontalWind < 0 ? -1 : 1) + Double(index) * 251
                let x = ((phase.truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span)) - 150
                let y = size.height * (0.13 + Double(index) * 0.16)
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addCurve(to: CGPoint(x: x + 105, y: y - 3), control1: CGPoint(x: x + 34, y: y - 12), control2: CGPoint(x: x + 65, y: y + 9))
                context.stroke(line, with: .color(SkyPalette.wind.opacity(0.10 + strength * 0.20)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        guard weather.precipitation != .none, weather.intensity > 0 else { return }
        let snow = weather.precipitation == .snow
        let count = min(weather.isHeavy ? Self.weatherParticles.count : 240, max(20, Int(size.width * size.height / 1_000_000 * weather.particleCountPerMillionPoints * (0.35 + weather.intensity))))
        let spanX = size.width + 60, spanY = size.height + 40
        func wrap(_ value: Double, _ span: Double) -> Double { (value.truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span) }
        for (index, particle) in Self.weatherParticles.prefix(count).enumerated() {
            let speed = (snow ? (9 + particle.speed * 11) : (46 + particle.speed * 32)) * (weather.isHeavy ? 1.55 : 1)
            let drift = time * weather.horizontalWind * (3 + min(12, weather.windKmh * 0.3))
            let x = wrap(particle.x * spanX + drift + (snow ? sin(time * 0.3 + Double(index)) * (weather.isHeavy ? 18 : 8) : 0), spanX) - 30
            let y = wrap(particle.y * spanY + time * speed, spanY) - 20
            if snow {
                let radius = (1.1 + particle.size * 1.5) * (weather.isHeavy ? 1.18 : 1)
                let color = SkyPalette.snow.opacity(sky.isDay ? 0.66 : 0.52)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(color))
                if index % 9 == 0 { cross(context, point: CGPoint(x: x + radius, y: y + radius), length: radius * 2, color: color.opacity(0.6)) }
            } else {
                var drop = Path()
                drop.move(to: CGPoint(x: x, y: y))
                drop.addLine(to: CGPoint(x: x + weather.horizontalWind * (2 + weather.windKmh * 0.06) * (weather.isHeavy ? 2 : 1), y: y + (8 + particle.size * 6) * (weather.isHeavy ? 1.6 : 1)))
                context.stroke(drop, with: .color(SkyPalette.rain.opacity(sky.isDay ? (weather.isHeavy ? 0.55 : 0.40) : (weather.isHeavy ? 0.42 : 0.28))), style: StrokeStyle(lineWidth: weather.isHeavy ? 1.1 : 0.85, lineCap: .round))
            }
        }
    }
}

/// Stop the 15 fps decoration when the window is hidden or fully covered.
private struct SkyWindowVisibility: NSViewRepresentable {
    var report: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { let view = VisibilityView(); view.report = report; return view }
    func updateNSView(_ nsView: VisibilityView, context: Context) { nsView.report = report }
    final class VisibilityView: NSView {
        var report: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastValue: Bool?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                             NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                        self?.updateVisibility(closing: notification.name == NSWindow.willCloseNotification)
                    })
                }
            }
            updateVisibility()
        }
        private func updateVisibility(closing: Bool = false) {
            let value = !closing && window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
            guard value != lastValue else { return }
            lastValue = value
            DispatchQueue.main.async { [weak self] in self?.report?(value) }
        }
        deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    }
}

private extension Date {
    static var referenceDate: Date { Date(timeIntervalSinceReferenceDate: 0) }
}
