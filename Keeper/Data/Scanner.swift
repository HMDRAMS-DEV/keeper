import Foundation

/// Finds the photos under a folder and groups each shot's files.
enum Scanner {
    struct Shot: Sendable, Equatable {
        var file: URL
        var companions: [URL]
    }

    /// Every photo file under `root`, skipping hidden files such as the `._` copies macOS leaves on cards.
    static func files(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where FileKind.isPhoto(url) && !url.lastPathComponent.hasPrefix("._") {
            if (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true { found.append(url) }
        }
        return found
    }

    /// Files with the same folder and name are one shot. The JPEG or HEIC leads, the RAW follows.
    static func shots(from files: [URL]) -> [Shot] {
        var groups: [String: [URL]] = [:]
        var order: [String] = []
        for url in files {
            let key = url.deletingPathExtension().path.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(url)
        }
        return order.map { key in
            let group = groups[key]!.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let lead = group.first { !FileKind.isRaw($0) } ?? group[0]
            return Shot(file: lead, companions: group.filter { $0 != lead })
        }
    }
}
