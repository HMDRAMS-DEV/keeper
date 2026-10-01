import AppKit

/// Memory cards and cameras that are plugged in, meaning any mounted disk with a DCIM folder.
enum Cards {
    struct Card: Identifiable, Hashable, Sendable {
        let name: String
        let root: URL
        var id: URL { root }
    }

    static func mounted() -> [Card] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        return volumes.compactMap { volume in
            let dcim = volume.appending(path: "DCIM", directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: dcim.path) else { return nil }
            let name = (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? volume.lastPathComponent
            return Card(name: name, root: dcim)
        }
    }
}
