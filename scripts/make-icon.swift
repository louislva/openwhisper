// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Squircle background
    let inset = 100 * s
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.05, alpha: 1)])!.draw(in: bg, angle: -90)
    NSColor(white: 1, alpha: 0.12).setStroke()
    bg.lineWidth = 4 * s
    bg.stroke()

    // Waveform bars
    let heights: [CGFloat] = [0.18, 0.34, 0.58, 0.82, 0.62, 0.40, 0.70, 0.46, 0.26, 0.14]
    let barWidth = 38 * s, gap = 22 * s
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (size - total) / 2 + 40 * s
    for (i, h) in heights.enumerated() {
        let height = h * 520 * s
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: size / 2 - height / 2, width: barWidth, height: height),
                               xRadius: barWidth / 2, yRadius: barWidth / 2)
        NSColor(white: 1, alpha: 0.55 + 0.45 * CGFloat(i) / CGFloat(heights.count)).setFill()
        bar.fill()
        x += barWidth + gap
    }

    // Recording dot
    let dot = NSBezierPath(ovalIn: NSRect(x: (size - total) / 2 - 60 * s, y: size / 2 - 32 * s, width: 64 * s, height: 64 * s))
    NSColor(red: 1, green: 0.27, blue: 0.27, alpha: 1).setFill()
    dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
