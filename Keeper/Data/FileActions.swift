import Foundation
import ImageIO

/// Changes to the files on the card. Every one of these can be undone.
enum FileActions {
    struct Trashed: Sendable {
        let original: URL
        let trashed: URL
    }

    enum Failure: LocalizedError {
        case cantRotate(String)

        var errorDescription: String? {
            switch self {
            case .cantRotate(let name): "\(name) can't be rotated in place."
            }
        }
    }

    /// Moves a file into this Mac's Trash. A file on a card moves off the card, so the space frees
    /// up right away instead of waiting in the card's hidden trash folder.
    static func trash(_ url: URL) throws -> Trashed {
        let fileManager = FileManager.default
        if onStartupDisk(url) {
            var result: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &result)
            return Trashed(original: url, trashed: (result as URL?) ?? url)
        }
        let bin = fileManager.homeDirectoryForCurrentUser.appending(path: ".Trash", directoryHint: .isDirectory)
        var destination = bin.appending(path: url.lastPathComponent)
        var copy = 1
        while fileManager.fileExists(atPath: destination.path) {
            copy += 1
            destination = bin.appending(path: "\(url.deletingPathExtension().lastPathComponent) \(copy).\(url.pathExtension)")
        }
        try fileManager.moveItem(at: url, to: destination)
        return Trashed(original: url, trashed: destination)
    }

    static func restore(_ item: Trashed) throws {
        try FileManager.default.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: item.trashed, to: item.original)
    }

    /// Turns a JPEG, HEIC, PNG, or TIFF by changing its orientation tag. The pixels aren't
    /// re-encoded, so nothing is lost. RAW files can't be rewritten this way.
    static func rotate(_ url: URL, turns: Int) throws {
        guard !FileKind.isRaw(url), let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else {
            throw Failure.cantRotate(url.lastPathComponent)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let current = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let next = Orientation.turned(current, by: turns)

        // Camera JPEGs always carry the tag, so change those two bytes in place. ImageIO refuses
        // to rewrite some camera JPEGs, such as the Sigma BF's.
        if let offset = try? jpegOrientationOffset(url) {
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset.position))
            let value = UInt16(next)
            try handle.write(contentsOf: offset.bigEndian ? [UInt8(value >> 8), UInt8(value & 0xFF)] : [UInt8(value & 0xFF), UInt8(value >> 8)])
            return
        }

        let temporary = url.deletingLastPathComponent().appending(path: ".keeper-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else {
            throw Failure.cantRotate(url.lastPathComponent)
        }
        let options: [CFString: Any] = [kCGImageDestinationOrientation: next]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else {
            throw Failure.cantRotate(url.lastPathComponent)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    /// Where the orientation value sits in a JPEG's EXIF block, if it has one.
    static func jpegOrientationOffset(_ url: URL) throws -> (position: Int, bigEndian: Bool)? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = [UInt8](try handle.read(upToCount: 128 * 1024) ?? Data())
        guard head.count > 4, head[0] == 0xFF, head[1] == 0xD8 else { return nil }

        var marker = 2
        while marker + 4 <= head.count, head[marker] == 0xFF {
            let kind = head[marker + 1]
            let length = Int(head[marker + 2]) << 8 | Int(head[marker + 3])
            if kind == 0xDA || kind == 0xD9 { return nil }
            let body = marker + 4
            if kind == 0xE1, body + 14 <= head.count, Array(head[body..<body + 6]) == Array("Exif\0\0".utf8) {
                let tiff = body + 6
                let bigEndian = head[tiff] == 0x4D
                func read16(_ at: Int) -> Int { bigEndian ? Int(head[at]) << 8 | Int(head[at + 1]) : Int(head[at + 1]) << 8 | Int(head[at]) }
                func read32(_ at: Int) -> Int { bigEndian ? read16(at) << 16 | read16(at + 2) : read16(at + 2) << 16 | read16(at) }
                let ifd = tiff + read32(tiff + 4)
                guard ifd + 2 <= head.count else { return nil }
                for index in 0..<read16(ifd) {
                    let entry = ifd + 2 + index * 12
                    guard entry + 12 <= head.count else { return nil }
                    if read16(entry) == 0x0112, read16(entry + 2) == 3 { return (entry + 8, bigEndian) }
                }
                return nil
            }
            marker = body + length - 2
        }
        return nil
    }

    private static func onStartupDisk(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let a = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let b = try? home.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        return a != nil && a == b
    }
}
