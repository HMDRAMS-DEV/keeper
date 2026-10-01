import CoreGraphics
import Foundation

/// What Keeper can tell about a photo on its own, on this Mac.
///
/// Sharpness is the variance of the Laplacian in the sharpest tile of a 4 x 4 grid. A portrait
/// with a soft background still has one sharp tile, so only a photo that is soft everywhere
/// counts as blurry. Exposure comes from the brightness histogram. The score is Apple's
/// on-device aesthetics model (Vision), from -1 to 1.
struct Quality: Codable, Hashable, Sendable {
    var sharpness: Double
    /// Mean brightness, 0 to 255.
    var brightness: Double
    /// Share of pixels that are nearly black.
    var shadows: Double
    /// Share of pixels that are nearly white.
    var highlights: Double
    var score: Double?

    enum Flag: String, CaseIterable, Sendable {
        case blurry, dark, bright, weak

        var label: String {
            switch self {
            case .blurry: "Blurry"
            case .dark: "Too dark"
            case .bright: "Too bright"
            case .weak: "Weak shot"
            }
        }
    }

    /// Set on 59 Sigma BF JPEGs: the sharpest original scored 153, and 57 of 59 copies blurred at
    /// sigma 6 scored under 110. Their brightness ran 84 to 168, and none scored under 0 for
    /// aesthetics. The aesthetics score barely moves for blur, so it only catches weak shots.
    static let blurryBelow = 110.0
    static let weakBelow = 0.0

    var flags: [Flag] {
        var flags: [Flag] = []
        if sharpness < Self.blurryBelow { flags.append(.blurry) }
        if brightness < 60 || (shadows > 0.4 && brightness < 80) { flags.append(.dark) }
        if brightness > 200 || (highlights > 0.25 && brightness > 170) { flags.append(.bright) }
        if let score, score < Self.weakBelow { flags.append(.weak) }
        return flags
    }

    /// Side of the square the measurements run on. Big enough to see focus, small enough to be quick.
    static let side = 512

    /// Measures an image. Pass a preview, not the original, for speed.
    static func measure(_ image: CGImage) -> Quality {
        let aspect = Double(image.width) / Double(max(image.height, 1))
        let width = aspect >= 1 ? side : max(8, Int(Double(side) * aspect))
        let height = aspect >= 1 ? max(8, Int(Double(side) / aspect)) : side
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            context?.interpolationQuality = .medium
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return measure(gray: pixels, width: width, height: height)
    }

    static func measure(gray: [UInt8], width: Int, height: Int) -> Quality {
        let count = Double(gray.count)
        var sum = 0.0, dark = 0, light = 0
        for value in gray {
            sum += Double(value)
            if value <= 12 { dark += 1 }
            if value >= 243 { light += 1 }
        }

        let tiles = 4
        var sharpest = 0.0
        for ty in 0..<tiles {
            for tx in 0..<tiles {
                let x0 = max(1, tx * width / tiles), x1 = min(width - 1, (tx + 1) * width / tiles)
                let y0 = max(1, ty * height / tiles), y1 = min(height - 1, (ty + 1) * height / tiles)
                var s = 0.0, s2 = 0.0, n = 0.0
                for y in y0..<y1 {
                    let row = y * width
                    for x in x0..<x1 {
                        let center = Int(gray[row + x])
                        let laplacian = Double(Int(gray[row + x - 1]) + Int(gray[row + x + 1]) + Int(gray[row - width + x]) + Int(gray[row + width + x]) - 4 * center)
                        s += laplacian
                        s2 += laplacian * laplacian
                        n += 1
                    }
                }
                guard n > 0 else { continue }
                let mean = s / n
                sharpest = max(sharpest, s2 / n - mean * mean)
            }
        }

        return Quality(sharpness: sharpest, brightness: sum / count, shadows: Double(dark) / count, highlights: Double(light) / count)
    }
}
