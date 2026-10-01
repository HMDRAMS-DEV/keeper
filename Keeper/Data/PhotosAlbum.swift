import AppKit
import Photos

/// Adds photos to a new album in Photos. Apple doesn't let apps make Shared Albums, so this makes
/// a regular album and opens Photos on it. Sharing it is then Share > Shared Albums in Photos.
enum PhotosAlbum {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            "Keeper can't add to Photos. Allow it in System Settings > Privacy & Security > Photos."
        }
    }

    /// Imports the photos (RAW files ride along with their JPEG) and returns the album's identifier.
    static func make(named name: String, from photos: [Photo]) async throws -> String {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw Failure.denied }

        let items = photos.map { (file: $0.file, raw: $0.rawCompanion) }
        nonisolated(unsafe) var albumID = ""
        try await PHPhotoLibrary.shared().performChanges {
            let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            albumID = album.placeholderForCreatedAssetCollection.localIdentifier
            var assets: [PHObjectPlaceholder] = []
            for item in items {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: item.file, options: nil)
                if let raw = item.raw {
                    request.addResource(with: .alternatePhoto, fileURL: raw, options: nil)
                }
                if let placeholder = request.placeholderForCreatedAsset { assets.append(placeholder) }
            }
            album.addAssets(assets as NSArray)
        }
        return albumID
    }

    /// Brings Photos forward showing the album. Falls back to just opening Photos.
    @MainActor
    static func reveal(_ albumID: String) {
        let script = NSAppleScript(source: """
        tell application "Photos"
            activate
            spotlight album id "\(albumID)"
        end tell
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil, let photos = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") {
            NSWorkspace.shared.openApplication(at: photos, configuration: .init())
        }
    }
}
