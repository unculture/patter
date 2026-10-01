// Draws the Wisp app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    // The macOS icon grid: an 824 pt body centered on a 1024 pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 30
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0x0B0B12).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0x221E3D), color(0x0C0C14)])!.draw(in: shape, angle: -90)

    // A soft glow behind the bars.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [color(0x7C5CFF, 0.38), color(0x45D6FA, 0.0)])!
        .draw(fromCenter: NSPoint(x: 512, y: 500), radius: 0, toCenter: NSPoint(x: 512, y: 500), radius: 430, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // The waveform: seven rounded bars, tallest in the middle.
    let heights: [CGFloat] = [0.20, 0.40, 0.64, 0.86, 0.64, 0.40, 0.20]
    let barWidth: CGFloat = 54
    let gap: CGFloat = 34
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let bars = NSBezierPath()
    for (index, height) in heights.enumerated() {
        let barHeight = height * 560
        let rect = NSRect(
            x: 512 - totalWidth / 2 + CGFloat(index) * (barWidth + gap),
            y: 512 - barHeight / 2,
            width: barWidth,
            height: barHeight)
        bars.append(NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2))
    }
    NSGradient(colors: [color(0x8C6BFF), color(0x5C94FF), color(0x45D6FA)])!.draw(in: bars, angle: -35)

    // A thin highlight on the top edge of the body.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 185, yRadius: 185)
    rim.lineWidth = 3
    color(0xFFFFFF, 0.10).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * factor)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
if iconutil.terminationStatus != 0 { exit(iconutil.terminationStatus) }
print("Wrote \(output.path)")
