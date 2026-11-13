import AppKit

let output = CommandLine.arguments[1]
let themeURL = URL(fileURLWithPath: CommandLine.arguments[2])
let theme = try JSONSerialization.jsonObject(with: Data(contentsOf: themeURL)) as! [String: Any]
let colors = theme["colors"] as! [String: String]
let opacity = theme["opacity"] as! [String: Double]
func color(_ name: String) -> NSColor {
    let text = colors[name]!.replacingOccurrences(of: "#", with: "")
    guard text.count == 6, let value = UInt32(text, radix: 16) else { fatalError("Invalid icon colour: \(name)") }
    return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
}
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for (size, name) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = AffineTransform(scale: scale)
    (transform as NSAffineTransform).concat()
    let rect = NSRect(x: 74, y: 74, width: 876, height: 876)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
    let shadow = NSShadow()
    shadow.shadowColor = color("iconShadow").withAlphaComponent(opacity["iconShadow"]!)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSGradient(starting: color("iconTop"), ending: color("iconBottom"))!.draw(in: shape, angle: -90)
    NSShadow().set()
    let circle = NSBezierPath()
    circle.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 290, startAngle: 102, endAngle: 446, clockwise: false)
    circle.lineWidth = 9
    circle.lineCapStyle = .round
    color("iconRing").withAlphaComponent(opacity["iconRing"]!).setStroke()
    circle.stroke()
    let leaf = NSImage(systemSymbolName: "leaf", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(paletteColors: [color("iconGlyph")]))!
    leaf.draw(in: NSRect(x: 273, y: 273, width: 478, height: 478))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}
