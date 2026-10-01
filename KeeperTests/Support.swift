import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Keeper

enum Fixtures {
    static func folder(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "KeeperTests/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A gradient with detail, or a flat field when `flat`.
    static func image(width: Int = 600, height: Int = 400, hue: Double = 0.1, flat: Bool = false, level: Double = 0.5) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        if flat {
            context.setFillColor(CGColor(gray: level, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            let colors = [CGColor(srgbRed: 1, green: 0.7 - hue, blue: 0.3, alpha: 1), CGColor(srgbRed: 0.2, green: 0.3, blue: 0.5 + hue, alpha: 1)]
            let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
            context.setLineWidth(2)
            for i in stride(from: 0, to: width, by: 9) {
                context.move(to: CGPoint(x: i, y: 0))
                context.addLine(to: CGPoint(x: i + height / 3, y: height))
            }
            context.strokePath()
        }
        return context.makeImage()!
    }

    static func jpeg(_ image: CGImage, at url: URL, orientation: UInt32 = 1) throws {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func orientation(of url: URL) -> UInt32? {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
    }

    static func photo(_ n: Int, preview: URL? = nil, quality: Quality? = nil) -> Photo {
        let file = URL(fileURLWithPath: "/Volumes/Card/DCIM/100/IMG_\(1000 + n).JPG")
        return Photo(id: file.path, file: file, companions: [], date: Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 30),
                     preview: preview ?? file, thumbnail: preview ?? file,
                     quality: quality ?? Quality(sharpness: 400, brightness: 120, shadows: 0.01, highlights: 0.01, score: 0.3))
    }
}
