import ImageIO
import SwiftUI

/// Decoded previews and thumbnails, kept in memory while they're near the screen. Decoding
/// happens off the main thread, so holding an arrow key never stutters.
@MainActor
final class Images {
    static let shared = Images()

    private let cache = NSCache<NSURL, CGImage>()
    private var pending: [URL: Task<CGImage?, Never>] = [:]

    private init() {
        cache.totalCostLimit = 900 * 1024 * 1024
    }

    func cached(_ url: URL) -> CGImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> CGImage? {
        if let image = cached(url) { return image }
        if let task = pending[url] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { Self.decode(url) }
        pending[url] = task
        let image = await task.value
        pending[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height) }
        return image
    }

    func prefetch(_ urls: [URL]) {
        for url in urls where cached(url) == nil && pending[url] == nil {
            Task { _ = await load(url) }
        }
    }

    nonisolated private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

struct Thumbnail: View {
    let url: URL
    var fill = false
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image = image ?? Images.shared.cached(url) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = Images.shared.cached(url)
            if image == nil { image = await Images.shared.load(url) }
        }
    }
}
