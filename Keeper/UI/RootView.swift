import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            switch library.phase {
            case .empty: WelcomeView()
            case .loading(let loading): LoadingView(loading: loading)
            case .ready: ReviewView()
            }
        }
        .overlay(alignment: .top) { NoticeView() }
        .onAppear {
            // `-KeeperOpen /path` opens a folder at launch, for trying things out.
            if library.phase == .empty, let path = UserDefaults.standard.string(forKey: "KeeperOpen") {
                library.open(URL(fileURLWithPath: path))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: { $0.hasDirectoryPath }) else { return false }
            library.open(folder)
            return true
        }
    }
}

/// The line about the last action, at the top of the window.
struct NoticeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        ZStack {
            if let notice = library.notice {
                Text(notice)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.canvas)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.ink.opacity(0.92), in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(notice)
            }
        }
        .padding(.top, 58)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: library.notice)
        .allowsHitTesting(false)
    }
}
