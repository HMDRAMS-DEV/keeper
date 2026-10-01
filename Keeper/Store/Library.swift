import AppKit
import Observation

/// The open card or folder: loading it, moving through it, selecting, and changing files.
@MainActor @Observable
final class Library {
    enum Phase: Equatable {
        case empty
        case loading(Loading)
        case ready
    }

    struct Loading: Equatable {
        var source: String
        var done = 0
        var total = 0
        var started = Date()
        var latest: URL?
    }

    enum Filter: String, CaseIterable {
        case all, flagged
    }

    private(set) var phase: Phase = .empty
    private(set) var source: URL?
    private(set) var sourceName = ""
    private(set) var photos: [Photo] = []
    var filter: Filter = .all {
        didSet { keepCurrentVisible() }
    }
    private(set) var currentID: Photo.ID?
    private(set) var selection: Set<Photo.ID> = []
    private var anchor: Photo.ID?
    private(set) var cards = Cards.mounted()
    /// A short line about the last action, shown for a few seconds.
    private(set) var notice: String?
    var zoomed = false
    /// The sheet that names a new Photos album is open.
    var askingForAlbum = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var undoStack: [(photos: [(index: Int, photo: Photo)], files: [FileActions.Trashed])] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cards = Cards.mounted() }
            }
        }
        Task.detached(priority: .background) { Previews.prune() }
    }

    /// For previews and tests.
    init(preview photos: [Photo], source: String = "Sigma BF") {
        self.photos = photos
        self.sourceName = source
        self.currentID = photos.first?.id
        self.phase = photos.isEmpty ? .empty : .ready
        self.cards = []
    }

    // MARK: - Derived

    var visible: [Photo] {
        filter == .all ? photos : photos.filter { !$0.flags.isEmpty }
    }

    var flaggedCount: Int { photos.count { !$0.flags.isEmpty } }

    var current: Photo? { currentID.flatMap { id in photos.first { $0.id == id } } }

    var currentPosition: Int? { currentID.flatMap { id in visible.firstIndex { $0.id == id } } }

    /// What an action applies to: the selection, or the photo on screen.
    var targets: [Photo] {
        selection.isEmpty ? (current.map { [$0] } ?? []) : photos.filter { selection.contains($0.id) }
    }

    /// A plugged-in card that isn't open yet.
    var newCard: Cards.Card? { cards.first { $0.root != source } }

    // MARK: - Loading

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        panel.message = "Choose a memory card or a folder of photos."
        panel.directoryURL = cards.first?.root ?? URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ root: URL, name: String? = nil) {
        loadTask?.cancel()
        let label = name ?? displayName(for: root)
        phase = .loading(Loading(source: label))
        loadTask = Task { [weak self] in
            let shots = await Task.detached(priority: .userInitiated) { Scanner.shots(from: Scanner.files(in: root)) }.value
            guard let self, !Task.isCancelled else { return }
            self.update { $0.total = shots.count }

            var loaded: [Photo] = []
            loaded.reserveCapacity(shots.count)
            let width = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
            await withTaskGroup(of: Photo?.self) { group in
                var next = 0
                func add() {
                    guard next < shots.count else { return }
                    let shot = shots[next]
                    next += 1
                    group.addTask(priority: .userInitiated) { await Previews.load(shot) }
                }
                for _ in 0..<width { add() }
                for await photo in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let photo { loaded.append(photo) }
                    self.update { loading in
                        loading.done += 1
                        if let photo { loading.latest = photo.thumbnail }
                    }
                    add()
                }
            }
            guard !Task.isCancelled else { return }

            self.photos = loaded.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
            self.source = root
            self.sourceName = label
            self.filter = .all
            self.selection = []
            self.anchor = nil
            self.undoStack = []
            self.zoomed = false
            self.currentID = self.photos.first?.id
            self.phase = .ready
            if shots.count > loaded.count {
                self.say("\(shots.count - loaded.count) files couldn't be read.")
            }
        }
    }

    func cancelLoading() {
        loadTask?.cancel()
        phase = photos.isEmpty ? .empty : .ready
    }

    private func update(_ change: (inout Loading) -> Void) {
        guard case .loading(var loading) = phase else { return }
        change(&loading)
        phase = .loading(loading)
    }

    private func displayName(for root: URL) -> String {
        if root.lastPathComponent == "DCIM" { return root.deletingLastPathComponent().lastPathComponent }
        return root.lastPathComponent
    }

    // MARK: - Moving and selecting

    /// Steps through the visible photos. With `extend`, grows the selection from where it started.
    func move(by step: Int, extend: Bool = false) {
        let list = visible
        guard !list.isEmpty else { return }
        let position = currentPosition ?? 0
        let target = min(max(position + step, 0), list.count - 1)
        if extend {
            let start = anchor ?? list[position].id
            anchor = start
            currentID = list[target].id
            selectRange(from: start, to: list[target].id)
        } else {
            currentID = list[target].id
            selection = []
            anchor = nil
        }
        zoomed = false
    }

    func jump(toEnd: Bool) {
        move(by: toEnd ? visible.count : -visible.count)
    }

    /// Clicking a thumbnail. Command toggles one photo, shift selects a range.
    func click(_ id: Photo.ID, command: Bool = false, shift: Bool = false) {
        if shift {
            let start = anchor ?? currentID ?? id
            anchor = start
            selectRange(from: start, to: id)
        } else if command {
            if selection.isEmpty, let currentID, currentID != id { selection.insert(currentID) }
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else {
            selection = []
            anchor = nil
        }
        currentID = id
        zoomed = false
    }

    func selectAll() {
        selection = Set(visible.map(\.id))
        anchor = visible.first?.id
    }

    func selectFlagged() {
        selection = Set(photos.filter { !$0.flags.isEmpty }.map(\.id))
        if let first = photos.first(where: { selection.contains($0.id) }) { currentID = first.id }
    }

    func clearSelection() {
        selection = []
        anchor = nil
    }

    private func selectRange(from start: Photo.ID, to end: Photo.ID) {
        let ids = visible.map(\.id)
        guard let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: end) else { return }
        selection = Set(ids[min(a, b)...max(a, b)])
    }

    private func keepCurrentVisible() {
        let list = visible
        selection = selection.filter { id in list.contains { $0.id == id } }
        if let currentID, list.contains(where: { $0.id == currentID }) { return }
        currentID = list.first?.id
    }

    // MARK: - Changing files

    /// Moves the targets and their RAW files to the Trash. Undo brings them back.
    func deleteTargets() {
        let doomed = targets
        guard !doomed.isEmpty else { return }
        let list = visible
        let nextID = list.first { photo in
            !doomed.contains { $0.id == photo.id } && (list.firstIndex(of: photo)! > (currentPosition ?? 0))
        }?.id ?? list.last { photo in !doomed.contains { $0.id == photo.id } }?.id

        var removed: [(index: Int, photo: Photo)] = []
        var trashed: [FileActions.Trashed] = []
        var failure: String?
        for photo in doomed {
            var moved: [FileActions.Trashed] = []
            do {
                for file in photo.files { moved.append(try FileActions.trash(file)) }
            } catch {
                // Put back what moved, so a shot never loses half its files.
                for item in moved { try? FileActions.restore(item) }
                failure = "\(photo.name): \(error.localizedDescription)"
                continue
            }
            trashed += moved
            if let index = photos.firstIndex(where: { $0.id == photo.id }) { removed.append((index, photo)) }
        }
        for item in removed.sorted(by: { $0.index > $1.index }) { photos.remove(at: item.index) }
        guard !removed.isEmpty else {
            say(failure ?? "Nothing was deleted.")
            return
        }
        undoStack.append((removed.sorted { $0.index < $1.index }, trashed))
        selection = []
        anchor = nil
        zoomed = false
        currentID = nextID
        let count = removed.count == 1 ? "1 photo" : "\(removed.count) photos"
        say(failure.map { "Moved \(count) to the Trash. Couldn't move \($0)" } ?? "Moved \(count) to the Trash. ⌘Z puts \(removed.count == 1 ? "it" : "them") back.")
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        var failed = 0
        for item in last.files {
            do { try FileActions.restore(item) } catch { failed += 1 }
        }
        for item in last.photos { photos.insert(item.photo, at: min(item.index, photos.count)) }
        currentID = last.photos.first?.photo.id
        selection = Set(last.photos.map(\.photo.id))
        if selection.count == 1 { selection = [] }
        say(failed == 0 ? "Put back \(last.photos.count == 1 ? "1 photo" : "\(last.photos.count) photos")." : "Put back all but \(failed) files. Check the Trash.")
    }

    /// Turns the targets. The screen turns right away. JPEG and HEIC files are turned on disk,
    /// then their previews are made again.
    func rotate(clockwise: Bool = true) {
        let turns = clockwise ? 1 : -1
        for photo in targets {
            guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { continue }
            photos[index].turns += turns
            let file = photo.file
            Task { [weak self] in
                let rotated = await Task.detached { () -> Result<Void, Error> in
                    Result { try FileActions.rotate(file, turns: turns) }
                }.value
                guard let self else { return }
                if case .failure(let error) = rotated {
                    self.say("\(error.localizedDescription) The turn shows here only.")
                    return
                }
                guard let current = self.photos.first(where: { $0.id == photo.id }),
                      let fresh = await Previews.refresh(current),
                      let index = self.photos.firstIndex(where: { $0.id == photo.id }) else { return }
                self.photos[index].preview = fresh.preview
                self.photos[index].thumbnail = fresh.thumbnail
                self.photos[index].turns -= turns
            }
        }
    }

    func makeAlbum(named name: String) {
        let picked = targets
        guard !picked.isEmpty else { return }
        say("Adding \(picked.count) to Photos…", sticky: true)
        Task {
            do {
                let album = try await PhotosAlbum.make(named: name, from: picked)
                say("Made “\(name)” in Photos. To share it, select all, then Share > Shared Albums.", seconds: 10)
                PhotosAlbum.reveal(album)
            } catch {
                say(error.localizedDescription, seconds: 8)
            }
        }
    }

    func say(_ text: String, seconds: Double = 4, sticky: Bool = false) {
        notice = text
        noticeTask?.cancel()
        guard !sticky else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
