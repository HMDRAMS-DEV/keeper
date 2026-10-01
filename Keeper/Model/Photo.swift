import Foundation

/// One shot. A camera that saves RAW and JPEG together makes one photo with two files: the
/// JPEG is what you see, the RAW travels with it when you delete or share.
struct Photo: Identifiable, Hashable, Sendable {
    /// The path of the main file when the card was read. It stays the same after a rotation.
    let id: String
    let file: URL
    /// Other files of the same shot, usually the RAW.
    let companions: [URL]
    let date: Date
    var preview: URL
    var thumbnail: URL
    var quality: Quality
    /// Quarter turns clockwise shown on screen but not yet in the preview.
    var turns = 0

    var files: [URL] { [file] + companions }
    var name: String { file.lastPathComponent }
    var hasRaw: Bool { FileKind.isRaw(file) || companions.contains(where: FileKind.isRaw) }
    var flags: [Quality.Flag] { quality.flags }

    /// The RAW file, when the main file is a JPEG or HEIC.
    var rawCompanion: URL? {
        FileKind.isRaw(file) ? nil : companions.first(where: FileKind.isRaw)
    }
}

enum FileKind {
    static let raw: Set<String> = ["arw", "cr2", "cr3", "crw", "dng", "erf", "fff", "iiq", "k25", "kdc", "mef", "mos", "mrw", "nef", "nrw", "orf", "pef", "raf", "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f", "3fr"]
    static let image: Set<String> = ["jpg", "jpeg", "heic", "heif", "hif", "png", "tif", "tiff"]

    static func isRaw(_ url: URL) -> Bool { raw.contains(url.pathExtension.lowercased()) }
    static func isPhoto(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return raw.contains(ext) || image.contains(ext)
    }
}
