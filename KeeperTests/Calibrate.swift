import CoreImage
import Foundation
import ImageIO
import Testing
@testable import Keeper

/// Prints sharpness, exposure, and score for real photos, and for blurred copies, to set the
/// thresholds in Quality. Run with TEST_RUNNER_KEEPER_CALIBRATE=/path/to/photos.
struct Calibrate {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KEEPER_CALIBRATE"] != nil))
    func calibrate() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KEEPER_CALIBRATE"]!)
        let files = Scanner.shots(from: Scanner.files(in: root)).map(\.file).filter { !FileKind.isRaw($0) }
        let step = max(1, files.count / 120)
        var lines: [String] = []
        let context = CIContext()
        for file in stride(from: 0, to: files.count, by: step).map({ files[$0] }) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: Previews.previewSide] as CFDictionary) else { continue }
            let q = Quality.measure(image)
            let blurred = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let qb = context.createCGImage(blurred, from: blurred.extent).map(Quality.measure)
            let score = try? await CalculateScore.score(image)
            lines.append(String(format: "%@\tsharp %.0f\tblur6 %.0f\tbright %.0f\tshadows %.2f\thigh %.2f\tscore %.2f", file.lastPathComponent, q.sharpness, qb?.sharpness ?? -1, q.brightness, q.shadows, q.highlights, score ?? -9))
        }
        try lines.joined(separator: "\n").write(to: FileManager.default.temporaryDirectory.appending(path: "keeper-calibration.tsv"), atomically: true, encoding: .utf8)
        print("Wrote \(lines.count) rows to", FileManager.default.temporaryDirectory.appending(path: "keeper-calibration.tsv").path)
    }
}

/// Times a cold load of a folder through the real pipeline. Run with TEST_RUNNER_KEEPER_TIME=/path.
@MainActor
struct LoadTiming {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KEEPER_TIME"] != nil))
    func coldLoad() async throws {
        try? FileManager.default.removeItem(at: Previews.folder)
        let library = Library()
        let start = Date()
        library.open(URL(fileURLWithPath: ProcessInfo.processInfo.environment["KEEPER_TIME"]!))
        while library.phase != .ready { try await Task.sleep(for: .milliseconds(50)) }
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        library.open(URL(fileURLWithPath: ProcessInfo.processInfo.environment["KEEPER_TIME"]!))
        while library.phase != .ready { try await Task.sleep(for: .milliseconds(20)) }
        print(String(format: "KEEPER_TIMING %d photos: cold %.1fs (%.0f ms each), warm %.2fs, flagged %d", library.photos.count, cold, cold * 1000 / Double(library.photos.count), Date().timeIntervalSince(warmStart), library.flaggedCount))
    }
}

import Vision
enum CalculateScore {
    static func score(_ image: CGImage) async throws -> Double {
        Double(try await CalculateImageAestheticsScoresRequest().perform(on: image).overallScore)
    }
}
