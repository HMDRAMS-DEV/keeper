import SwiftUI

/// Before anything is open: plugged-in cards, and a way to pick a folder.
struct WelcomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: Theme.appIcon)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.bottom, 18)
            Text("Sift a card in minutes.")
                .display(34)
                .foregroundStyle(Theme.ink)
            Text("Keeper reads every photo once. Then it's arrow keys,\nDelete for the misses, and a Photos album for the keepers.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)

            VStack(spacing: 10) {
                ForEach(library.cards) { card in
                    Button {
                        library.open(card.root, name: card.name)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "sdcard.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 40)
                                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                                Text("Plugged in").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("Open").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                        }
                        .padding(12)
                        .frame(width: 380)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 30)

            Button("Choose a Folder…") { library.chooseFolder() }
                .buttonStyle(PillButtonStyle(prominent: library.cards.isEmpty))
                .padding(.top, library.cards.isEmpty ? 30 : 16)
            Text("or drop one here · ⌘O")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
