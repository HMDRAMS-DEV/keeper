// Draws the background for Keeper's disk image window: warm paper, a faint dot grid,
// and a dotted arrow from the app to the Applications folder.
//
//     swift scripts/render-dmg-background.swift <output.tiff>
//
// Writes a TIFF holding 1x and 2x images, which Finder picks between on Retina screens.

import AppKit

let size = CGSize(width: 640, height: 400)
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dmg-background.tiff")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw() {
    color(0xF7F5F3).setFill()
    NSRect(origin: .zero, size: size).fill()

    // The dot grid, like the charts in the app.
    color(0x0D0D0D, 0.07).setFill()
    for x in stride(from: 12.0, to: size.width, by: 16) {
        for y in stride(from: 12.0, to: size.height, by: 16) {
            NSBezierPath(ovalIn: NSRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
        }
    }

    // A dotted arrow between the two icons, which Finder places at y = 190 from the top.
    let y = size.height - 190
    let dots = stride(from: 250.0, through: 380, by: 13)
    for (index, x) in dots.enumerated() {
        let t = CGFloat(index) / CGFloat(dots.underestimatedCount - 1)
        color(0xF06418, 0.35 + 0.65 * t).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)).fill()
    }
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 386, y: y + 11))
    head.line(to: NSPoint(x: 398, y: y))
    head.line(to: NSPoint(x: 386, y: y - 11))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    color(0xF06418).setStroke()
    head.stroke()

    let title = NSAttributedString(string: "Drag Keeper to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: color(0x0D0D0D),
        .kern: -0.4,
    ])
    title.draw(at: NSPoint(x: (size.width - title.size().width) / 2, y: 62))
    let subtitle = NSAttributedString(string: "Then open it from Applications.", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: color(0x85807B),
    ])
    subtitle.draw(at: NSPoint(x: (size.width - subtitle.size().width) / 2, y: 38))
}

func image(scale: CGFloat) -> NSBitmapImageRep {
    // Tagged sRGB, so Finder shows the colors as written instead of treating them as device values.
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!.retagging(with: .sRGB)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [image(scale: 1), image(scale: 2)], using: .lzw, factor: 0)!
try tiff.write(to: output)
print("Wrote \(output.path)")
