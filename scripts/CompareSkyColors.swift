import AppKit

let before = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let after = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[3])
let width = 1760
let height = 2500
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.969, green: 0.976, blue: 0.984, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let textColor = NSColor(srgbRed: 0.13, green: 0.20, blue: 0.28, alpha: 1)
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .medium) {
    (text as NSString).draw(in: NSRect(x: x, y: y, width: 820, height: size + 12),
                           withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: textColor])
}
label("之前", x: 40, y: 2442, size: 27)
label("修改后 · 更蓝、更亮，保留日月遮挡", x: 900, y: 2442, size: 27)
let scenes = [("sky-09.0.png", "白天 09:00"), ("sky-06.2.png", "日出 06:15"), ("sky-17.5.png", "黄昏 17:30")]
for (row, item) in scenes.enumerated() {
    let top = CGFloat(2404 - row * 790)
    label(item.1, x: 40, y: top - 30, size: 23)
    for (column, directory) in [before, after].enumerated() {
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(item.0)) else {
            fputs("Missing preview: \(item.0)\n", stderr); exit(1)
        }
        let imageWidth: CGFloat = 820
        let imageHeight = imageWidth * image.size.height / image.size.width
        image.draw(in: NSRect(x: CGFloat(20 + column * 860), y: top - 48 - imageHeight,
                             width: imageWidth, height: imageHeight))
    }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
print(destination.path)
