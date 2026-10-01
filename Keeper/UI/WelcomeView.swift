import SwiftUI

/// Before anything is open: plugged-in cards, recent folders, and a way to pick a folder.
struct WelcomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: Theme.appIcon)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.bottom, 18)
            Text("Open a card or folder")
                .display(34)
                .foregroundStyle(Theme.ink)
            Text("Keeper loads every photo once. Then go through them with\nthe arrow keys, delete the misses, and keep the rest.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)

            VStack(spacing: 8) {
                ForEach(library.cards) { card in
                    SourceRow(symbol: "sdcard.fill", title: card.name, detail: "Plugged in", highlighted: true) {
                        library.open(card.root, name: card.name)
                    }
                }
                ForEach(library.recents.filter { recent in !library.cards.contains { $0.root.path == recent.path } }.prefix(5)) { recent in
                    SourceRow(symbol: "folder.fill", title: recent.name, detail: (recent.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath) {
                        library.open(recent.url, name: recent.name)
                    }
                }
            }
            .padding(.top, 30)

            Button("Choose a Folder…") { library.chooseFolder() }
                .buttonStyle(PillButtonStyle(prominent: library.cards.isEmpty))
                .padding(.top, library.cards.isEmpty && library.recents.isEmpty ? 30 : 18)
            Text("or drop one here · ⌘O")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A card or folder you can open with one click.
struct SourceRow: View {
    let symbol: String
    let title: String
    let detail: String
    var highlighted = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(highlighted ? Theme.accent : Theme.muted)
                    .frame(width: 38, height: 38)
                    .background(highlighted ? Theme.accent.opacity(0.14) : Theme.quietWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text("Open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(highlighted || hovering ? 1 : 0)
            }
            .padding(10)
            .frame(width: 400)
            .background(hovering || highlighted ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
