import Foundation
import Testing
@testable import Keeper

struct OrientationTests {
    @Test func turnsClockwise() {
        #expect(Orientation.turned(1, by: 1) == 6)
        #expect(Orientation.turned(1, by: 2) == 3)
        #expect(Orientation.turned(1, by: -1) == 8)
        #expect(Orientation.turned(6, by: -1) == 1)
    }

    @Test func fourTurnsComeBack() {
        for value in UInt32(1)...8 {
            #expect(Orientation.turned(value, by: 4) == value)
            #expect(Orientation.turned(Orientation.turned(value, by: 1), by: -1) == value)
        }
    }
}

struct QualityTests {
    @Test func flatGrayIsBlurry() {
        let quality = Quality.measure(Fixtures.image(flat: true, level: 0.5))
        #expect(quality.flags == [.blurry])
    }

    @Test func detailIsSharp() {
        #expect(!Quality.measure(Fixtures.image()).flags.contains(.blurry))
    }

    @Test func exposure() {
        #expect(Quality.measure(Fixtures.image(flat: true, level: 0.03)).flags.contains(.dark))
        #expect(Quality.measure(Fixtures.image(flat: true, level: 0.98)).flags.contains(.bright))
        #expect(!Quality.measure(Fixtures.image()).flags.contains(.dark))
    }

    @Test func weakScore() {
        let quality = Quality(sharpness: 500, brightness: 120, shadows: 0, highlights: 0, score: -0.2)
        #expect(quality.flags == [.weak])
    }
}

struct ScannerTests {
    @Test func pairsRawWithJpeg() throws {
        let folder = try Fixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["BF_001.JPG", "BF_001.DNG", "BF_002.DNG", "BF_003.jpg", "._BF_003.jpg", "notes.txt"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: Data([0]))
        }
        let shots = Scanner.shots(from: Scanner.files(in: folder)).sorted { $0.file.lastPathComponent < $1.file.lastPathComponent }
        #expect(shots.map(\.file.lastPathComponent) == ["BF_001.JPG", "BF_002.DNG", "BF_003.jpg"])
        #expect(shots[0].companions.map(\.lastPathComponent) == ["BF_001.DNG"])
        #expect(shots[1].companions.isEmpty)
    }
}

struct FileActionTests {
    @Test func rotateRewritesOnlyTheTag() throws {
        let folder = try Fixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "shot.jpg")
        try Fixtures.jpeg(Fixtures.image(), at: url)
        let before = try Data(contentsOf: url).count
        try FileActions.rotate(url, turns: 1)
        #expect(Fixtures.orientation(of: url) == 6)
        try FileActions.rotate(url, turns: -1)
        #expect(Fixtures.orientation(of: url) == 1)
        let after = try Data(contentsOf: url).count
        #expect(after == before)
        #expect(try FileActions.jpegOrientationOffset(url) != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["shot.jpg"])
    }

    @Test func rawCantRotate() throws {
        #expect(throws: FileActions.Failure.self) { try FileActions.rotate(URL(fileURLWithPath: "/tmp/x.DNG"), turns: 1) }
    }

    @Test func trashAndRestore() throws {
        let folder = try Fixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "keeper-trash-test-\(UUID().uuidString).jpg")
        try Data([1, 2, 3]).write(to: url)
        let item = try FileActions.trash(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try FileActions.restore(item)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
struct LibraryTests {
    @Test func shiftArrowsSelectARun() {
        let library = Library(preview: (0..<6).map { Fixtures.photo($0) })
        library.move(by: 1)
        library.move(by: 1, extend: true)
        library.move(by: 1, extend: true)
        #expect(library.selection == Set((1...3).map { Fixtures.photo($0).id }))
        library.move(by: -2, extend: true)
        #expect(library.selection == Set((1...1).map { Fixtures.photo($0).id }))
        library.move(by: 1)
        #expect(library.selection.isEmpty)
        #expect(library.currentID == Fixtures.photo(2).id)
    }

    @Test func targetsFallBackToCurrent() {
        let library = Library(preview: (0..<3).map { Fixtures.photo($0) })
        #expect(library.targets.map(\.id) == [Fixtures.photo(0).id])
        library.click(Fixtures.photo(2).id, command: true)
        #expect(library.targets.map(\.id) == [Fixtures.photo(0).id, Fixtures.photo(2).id])
    }

    @Test func flaggedFilterMovesOffHiddenPhoto() {
        var photos = (0..<4).map { Fixtures.photo($0) }
        photos[2].quality.sharpness = 1
        let library = Library(preview: photos)
        library.filter = .flagged
        #expect(library.visible.map(\.id) == [photos[2].id])
        #expect(library.currentID == photos[2].id)
        #expect(library.flaggedCount == 1)
    }
}
