import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Reads each shot once and keeps a screen-sized preview and a thumbnail on this Mac's disk, so
/// flipping through a card is instant. Opening the same card again reuses them.
enum Previews {
    static let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: "com.ramihmd.keeper/previews", directoryHint: .isDirectory)
    }()

    static let previewSide = 2560
    static let thumbnailSide = 240

    private struct Meta: Codable {
        var date: Date
        var quality: Quality
    }

    /// Makes or reuses the preview, thumbnail, and quality for a shot. Nil if the file can't be read.
    static func load(_ shot: Scanner.Shot) async -> Photo? {
        guard let entry = entry(for: shot.file) else { return nil }
        let preview = entry.appending(path: "preview.jpg")
        let thumbnail = entry.appending(path: "thumb.jpg")
        let metaURL = entry.appending(path: "meta.json")

        if let data = try? Data(contentsOf: metaURL), let meta = try? JSONDecoder().decode(Meta.self, from: data),
           FileManager.default.fileExists(atPath: preview.path), FileManager.default.fileExists(atPath: thumbnail.path) {
            return Photo(id: shot.file.path, file: shot.file, companions: shot.companions, date: meta.date,
                         preview: preview, thumbnail: thumbnail, quality: meta.quality)
        }

        guard let source = CGImageSourceCreateWithURL(shot.file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = render(source, side: previewSide) else { return nil }
        let date = captureDate(source) ?? modificationDate(shot.file) ?? .distantPast
        var quality = Quality.measure(image)
        quality.score = await aesthetics(image)

        do {
            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
            try write(image, to: preview, quality: 0.85)
            try write(scaled(image, side: thumbnailSide) ?? image, to: thumbnail, quality: 0.8)
            try JSONEncoder().encode(Meta(date: date, quality: quality)).write(to: metaURL)
        } catch {
            return nil
        }
        return Photo(id: shot.file.path, file: shot.file, companions: shot.companions, date: date,
                     preview: preview, thumbnail: thumbnail, quality: quality)
    }

    /// Makes a fresh preview and thumbnail after the file changed on disk, as after a rotation.
    static func refresh(_ photo: Photo) async -> Photo? {
        guard var fresh = await load(Scanner.Shot(file: photo.file, companions: photo.companions)) else { return nil }
        fresh = Photo(id: photo.id, file: fresh.file, companions: fresh.companions, date: photo.date,
                      preview: fresh.preview, thumbnail: fresh.thumbnail, quality: fresh.quality)
        return fresh
    }

    /// Removes previews nobody has opened in two weeks.
    static func prune(olderThan age: TimeInterval = 14 * 86400) {
        let keys: [URLResourceKey] = [.contentAccessDateKey, .contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for entry in entries {
            let values = try? entry.appending(path: "meta.json").resourceValues(forKeys: Set(keys))
            let used = [values?.contentAccessDate, values?.contentModificationDate].compactMap { $0 }.max() ?? .distantPast
            if used < cutoff { try? FileManager.default.removeItem(at: entry) }
        }
    }

    /// The full-size image, for checking focus up close.
    static func original(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let size = pixelSize(source)
        return render(source, side: max(size.width, size.height, 1))
    }

    // MARK: - Helpers

    /// One folder per file version. Path, size, and modification time name it, so an edited file gets a new one.
    private static func entry(for url: URL) -> URL? {
        // URL caches resource values, and a rotated file keeps its URL. Read them fresh.
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        let key = "\(url.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: hash, directoryHint: .isDirectory)
    }

    private static func render(_ source: CGImageSource, side: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, properties?[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private static func scaled(_ image: CGImage, side: Int) -> CGImage? {
        let scale = Double(side) / Double(max(image.width, image.height))
        guard scale < 1 else { return image }
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func captureDate(_ source: CGImageSource) -> Date? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard let text = exif?[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func aesthetics(_ image: CGImage) async -> Double? {
        guard let observation = try? await CalculateImageAestheticsScoresRequest().perform(on: image) else { return nil }
        return Double(observation.overallScore)
    }
}
