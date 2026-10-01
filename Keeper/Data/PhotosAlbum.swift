import AppKit
import Photos

/// Adds photos to the Photos library, optionally inside a new album. Apple doesn't let apps make
/// Shared Albums, so this makes a regular album and opens Photos on it. Sharing it is then
/// Share > Shared Albums in Photos.
enum PhotosAlbum {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            "Keeper can't add to Photos. Allow it in System Settings > Privacy & Security > Photos."
        }
    }

    /// Imports the photos (RAW files ride along with their JPEG). With an album name, also puts them
    /// in a new album and returns its identifier.
    static func add(_ photos: [Photo], toAlbum name: String?) async throws -> String? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw Failure.denied }

        let items = photos.map { (file: $0.file, raw: $0.rawCompanion) }
        nonisolated(unsafe) var albumID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let album = name.map { PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: $0) }
            albumID = album?.placeholderForCreatedAssetCollection.localIdentifier
            var assets: [PHObjectPlaceholder] = []
            for item in items {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: item.file, options: nil)
                if let raw = item.raw {
                    request.addResource(with: .alternatePhoto, fileURL: raw, options: nil)
                }
                if let placeholder = request.placeholderForCreatedAsset { assets.append(placeholder) }
            }
            album?.addAssets(assets as NSArray)
        }
        return albumID
    }

    /// Brings Photos forward showing the album, or just opens Photos without one.
    @MainActor
    static func reveal(_ albumID: String?) {
        guard let albumID else { return openPhotos() }
        let script = NSAppleScript(source: """
        tell application "Photos"
            activate
            spotlight album id "\(albumID)"
        end tell
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil { openPhotos() }
    }

    @MainActor
    private static func openPhotos() {
        guard let photos = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos") else { return }
        NSWorkspace.shared.openApplication(at: photos, configuration: .init())
    }
}
