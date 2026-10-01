// Renders Keeper's app icon into the asset catalog, plus light and dark copies for the website.
//
//     swift scripts/render-icon.swift
//
// A contact sheet, reduced to its idea: a 3 x 3 grid of faint frames, one roll of shots. The
// middle one is the keeper. It lifts out of the grid, bigger, in golden-hour color, with the
// sun as the dot that ends Keeper's wordmark. Same tile and grid as Pacer's icon, so they read
// as a family.

import AppKit

let output = URL(fileURLWithPath: "Keeper/Assets.xcassets/AppIcon.appiconset")
let site = URL(fileURLWithPath: "site/assets")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: locations)!
}

func draw(in context: CGContext, size: CGFloat, dark: Bool) {
    let scale = size / 1024
    context.scaleBy(x: scale, y: scale)

    // The macOS icon grid: an 824pt rounded square centered on a 1024pt canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    context.addPath(shape)
    context.setFillColor(color(dark ? 0x161618 : 0xF7F5F3))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = dark ? gradient([color(0x2A2A2E), color(0x0E0E10)]) : gradient([color(0xFFFFFF), color(0xEEEAE5)])
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    context.saveGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.setStrokeColor(dark ? color(0xFFFFFF, 0.08) : color(0x000000, 0.06))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // The roll: 3:2 frames on the same 150pt pitch as Pacer's dots, wider across.
    let width: CGFloat = 150, height: CGFloat = 100, pitchX: CGFloat = 186, pitchY: CGFloat = 136
    let line: CGFloat = 12, corner: CGFloat = 20
    for column in 0..<3 {
        for row in 0..<3 where !(column == 1 && row == 1) {
            let center = CGPoint(x: 512 + pitchX * CGFloat(column - 1), y: 512 + pitchY * CGFloat(row - 1))
            let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
            context.addPath(CGPath(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.setStrokeColor(dark ? color(0xFFFFFF, 0.2) : color(0x0D0D0D, 0.14))
            context.setLineWidth(line)
            context.strokePath()
        }
    }

    // The keeper: lifted, larger, full of late light.
    let keeper = CGRect(x: 512 - 150, y: 512 - 100, width: 300, height: 200)
    let keeperPath = CGPath(roundedRect: keeper, cornerWidth: 34, cornerHeight: 34, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(dark ? 0x000000 : 0x7A3A10, dark ? 0.55 : 0.32))
    context.addPath(keeperPath)
    context.setFillColor(color(0xF06418))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(keeperPath)
    context.clip()
    context.drawLinearGradient(gradient([color(0xFFC53D), color(0xFF8A3D), color(0xE8490F)], [0, 0.5, 1]),
                               start: CGPoint(x: 512, y: keeper.maxY), end: CGPoint(x: 512, y: keeper.minY), options: [])
    // The sun, low over a horizon, and its glow.
    let sun = CGPoint(x: 512 + 58, y: 512 - 8)
    context.drawRadialGradient(gradient([color(0xFFFFFF, 0.55), color(0xFFFFFF, 0)]), startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 120, options: [])
    context.setFillColor(color(0xFFFBF2))
    context.fillEllipse(in: CGRect(x: sun.x - 36, y: sun.y - 36, width: 72, height: 72))
    context.setFillColor(color(0xB8360A, 0.9))
    context.fill(CGRect(x: keeper.minX, y: keeper.minY, width: keeper.width, height: 62))
    context.restoreGState()

    // A white rim, like a print's border catching the light.
    context.addPath(CGPath(roundedRect: keeper.insetBy(dx: 3, dy: 3), cornerWidth: 31, cornerHeight: 31, transform: nil))
    context.setStrokeColor(color(0xFFFFFF, 0.5))
    context.setLineWidth(6)
    context.strokePath()
}

func png(pixels: Int, dark: Bool = false) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    draw(in: context.cgContext, size: CGFloat(pixels), dark: dark)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: output.appending(path: name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: output.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")

try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
for dark in [false, true] {
    let suffix = dark ? "-dark" : ""
    try png(pixels: 512, dark: dark).write(to: site.appending(path: "icon\(suffix).png"))
    try png(pixels: 64, dark: dark).write(to: site.appending(path: "favicon\(suffix).png"))
}
print("Wrote light and dark icons to \(site.path)")
