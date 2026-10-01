import SwiftUI

/// One photo big, the roll along the bottom, and the keys along the edge.
struct ReviewView: View {
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            TopBar()
            ZStack(alignment: .bottom) {
                if library.visible.isEmpty {
                    Text(library.filter == .flagged ? "Nothing flagged. Press F to see everything." : "No photos here.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let photo = library.current {
                    Stage(photo: photo, selected: library.selection.contains(photo.id), zoomed: library.zoomed, captioned: library.selection.isEmpty)
                        .id(photo.id)
                }
                if !library.selection.isEmpty {
                    SelectionBar()
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: library.selection.isEmpty)
            Filmstrip()
            Legend()
        }
        .modifier(KeyMonitor(library: library))
        .sheet(isPresented: $library.askingForAlbum) { AlbumSheet() }
        .onChange(of: library.currentID, initial: true) { prefetch() }
    }

    /// Decodes the neighbors so the next arrow press is instant.
    private func prefetch() {
        let list = library.visible
        guard let position = library.currentPosition else { return }
        let near = [1, -1, 2, 3, -2].map { position + $0 }.filter { list.indices.contains($0) }
        Images.shared.prefetch(near.map { list[$0].preview })
    }
}

struct TopBar: View {
    @Environment(Library.self) private var library
    private let updater = Updater.shared

    var body: some View {
        HStack(spacing: 14) {
            Wordmark(size: 18)
            Text("\(library.sourceName) · \(Format.count(library.photos.count))")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer()
            if let version = updater.available {
                Button("Update to \(version)") { updater.check() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
            if let card = library.newCard {
                Button {
                    library.open(card.root, name: card.name)
                } label: {
                    Label("Open \(card.name)", systemImage: "sdcard.fill")
                }
                .buttonStyle(PillButtonStyle())
            }
            HStack(spacing: 4) {
                FilterChip(title: "All", count: library.photos.count, on: library.filter == .all) { library.filter = .all }
                FilterChip(title: "Flagged", count: library.flaggedCount, on: library.filter == .flagged) { library.filter = .flagged }
            }
            .padding(3)
            .background(Theme.quietWash, in: Capsule())
            .help("Flagged photos look blurry, too dark, too bright, or weak. Press F to switch.")
            IconButton(symbol: "folder", help: "Open a card or folder (⌘O)") { library.chooseFolder() }
        }
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .frame(height: 52)
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Text(count.formatted()).foregroundStyle(on ? .white.opacity(0.8) : Theme.muted)
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(on ? .white : Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(on ? Theme.accent : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

/// The photo, as big as the window allows.
struct Stage: View {
    let photo: Photo
    let selected: Bool
    let zoomed: Bool
    var captioned = true

    @State private var image: CGImage?
    @State private var shownID: Photo.ID?
    @State private var original: CGImage?

    var body: some View {
        GeometryReader { proxy in
            let area = proxy.size
            ZStack {
                if zoomed, let original {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: original, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    }
                    .defaultScrollAnchor(.center)
                } else if let image = image ?? Images.shared.cached(photo.preview) {
                    let turned = abs(photo.turns) % 2 == 1
                    let pixels = CGSize(width: image.width, height: image.height)
                    let fit = fitted(turned ? CGSize(width: pixels.height, height: pixels.width) : pixels, in: CGSize(width: area.width - 64, height: area.height - 72))
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: turned ? fit.height : fit.width, height: turned ? fit.width : fit.height)
                        .overlay {
                            if selected {
                                Rectangle().strokeBorder(Theme.accent, lineWidth: 4)
                            }
                        }
                        .rotationEffect(.degrees(Double(photo.turns) * 90))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: photo.turns)
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
                        .position(x: area.width / 2, y: (area.height - 40) / 2 + 8)
                }
                if zoomed && original == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: area.width, height: area.height)
            .overlay(alignment: .topLeading) { FlagChips(flags: photo.flags).padding(20) }
            .overlay(alignment: .bottom) { if captioned && !zoomed { caption.padding(.bottom, 12) } }
        }
        .task(id: photo.preview) {
            if let cached = Images.shared.cached(photo.preview) {
                image = cached
            } else {
                let loaded = await Images.shared.load(photo.preview)
                if !Task.isCancelled { image = loaded }
            }
        }
        .task(id: zoomed ? photo.id : nil) {
            original = nil
            guard zoomed else { return }
            let file = photo.file
            original = await Task.detached(priority: .userInitiated) { Previews.original(file) }.value
        }
    }

    private var caption: some View {
        HStack(spacing: 8) {
            Text(photo.name).foregroundStyle(Theme.ink)
            if photo.rawCompanion != nil {
                Text("RAW")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Theme.quietWash, in: Capsule())
            }
            Text("·")
            Text(Format.shot(photo.date))
            if let score = photo.quality.score {
                Text("·")
                Text("Score \(Int(((score + 1) * 50).rounded()))")
                    .help("Apple's on-device aesthetics score, 0 to 100")
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.muted)
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

struct FlagChips: View {
    let flags: [Quality.Flag]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(flags, id: \.self) { flag in
                HStack(spacing: 5) {
                    Circle().fill(Theme.hot).frame(width: 6, height: 6)
                    Text(flag.label)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.card, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
        }
    }
}

/// The roll. Click to jump, command-click to pick, shift-click to pick a run.
struct Filmstrip: View {
    @Environment(Library.self) private var library

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(library.visible) { photo in
                        Frame(photo: photo, current: photo.id == library.currentID, selected: library.selection.contains(photo.id))
                            .id(photo.id)
                            .onTapGesture {
                                let flags = NSEvent.modifierFlags
                                library.click(photo.id, command: flags.contains(.command), shift: flags.contains(.shift))
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(height: 84)
            .onChange(of: library.currentID, initial: true) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(id, anchor: .center) }
            }
        }
        .background(Theme.card.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    struct Frame: View {
        let photo: Photo
        let current: Bool
        let selected: Bool

        var body: some View {
            Thumbnail(url: photo.thumbnail, fill: true)
                .rotationEffect(.degrees(Double(photo.turns) * 90))
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : current ? Theme.ink : .clear, lineWidth: selected ? 3 : 2)
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white, Theme.accent)
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !photo.flags.isEmpty {
                        Circle().fill(Theme.hot).frame(width: 7, height: 7)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .padding(5)
                    }
                }
                .opacity(current || selected ? 1 : 0.72)
                .scaleEffect(current ? 1.06 : 1)
                .animation(.easeOut(duration: 0.12), value: current)
                .contentShape(Rectangle())
        }
    }
}

/// What you can do with the photos you picked.
struct SelectionBar: View {
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 8) {
            Text("\(library.selection.count.formatted()) selected")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            ShareLink(items: library.targets.map(\.file)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .help("AirDrop, Messages, or Mail")
            Button {
                library.askingForAlbum = true
            } label: {
                Label("Photos Album", systemImage: "rectangle.stack.badge.plus")
            }
            .buttonStyle(PillButtonStyle())
            .help("Make an album in Photos (P)")
            Button {
                library.deleteTargets()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(PillButtonStyle(tint: Theme.hot))
            .help("Move to the Trash (⌫)")
            IconButton(symbol: "xmark", help: "Clear the selection (esc)", size: 28) { library.clearSelection() }
        }
        .padding(6)
        .background(Theme.card, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 18, y: 6)
    }
}

struct Legend: View {
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 16) {
            KeyCap(key: "← →", label: "Browse")
            KeyCap(key: "⇧ →", label: "Select")
            KeyCap(key: "R", label: "Rotate")
            KeyCap(key: "⌫", label: "Delete")
            KeyCap(key: "Z", label: "Zoom")
            KeyCap(key: "P", label: "Photos album")
            KeyCap(key: "F", label: "Flagged")
            KeyCap(key: "⌘Z", label: "Undo")
            Spacer()
            if let position = library.currentPosition {
                Text("\((position + 1).formatted()) of \(library.visible.count.formatted())")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 36)
        .background(Theme.card.opacity(0.6))
    }
}

/// Names the new Photos album.
struct AlbumSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        let count = library.targets.count
        VStack(alignment: .leading, spacing: 14) {
            Text("New Photos album").display(22)
            Text("Keeper adds \(Format.count(count)) to a new album and opens Photos on it. From there, select all and choose Share > Shared Albums to invite people.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Album name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button("Add \(Format.count(count))", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            let date = library.targets.first?.date ?? Date()
            name = "\(library.sourceName) · \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dismiss()
        library.makeAlbum(named: trimmed)
    }
}
