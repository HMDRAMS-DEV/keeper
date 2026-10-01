import SwiftUI

/// Reading the card. Every photo gets a preview and a quality check, once.
struct LoadingView: View {
    @Environment(Library.self) private var library
    let loading: Library.Loading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.quietWash)
                if let latest = loading.latest {
                    Thumbnail(url: latest, fill: true)
                        .id(latest)
                        .transition(.opacity)
                }
            }
            .frame(width: 132, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: loading.latest)
            .padding(.bottom, 26)

            Text(loading.total == 0 ? "Finding photos on \(loading.source)" : "Reading \(loading.source)")
                .display(30)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text("Each photo gets a sharp preview and a quick check for blur and exposure. Opening this card again will be instant.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.muted)
                .lineSpacing(2)
                .padding(.top, 8)

            ProgressTrack(value: loading.total == 0 ? nil : Double(loading.done) / Double(loading.total))
                .padding(.top, 26)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Text(loading.total == 0 ? "Looking…" : "\(loading.done.formatted()) of \(Format.count(loading.total))")
                    Spacer()
                    if let left = Format.remaining(done: loading.done, total: loading.total, since: loading.started, now: context.date) {
                        Text(left)
                    }
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.muted)
            }
            .padding(.top, 10)

            Button("Cancel") { library.cancelLoading() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .padding(.top, 28)
        }
        .frame(width: 440)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A calm progress bar. With no value yet, a short segment sweeps across.
struct ProgressTrack: View {
    let value: Double?
    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.quietWash)
                if let value {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accentSoft, Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * min(max(value, 0), 1)))
                        .animation(.easeOut(duration: 0.25), value: value)
                } else {
                    Capsule().fill(Theme.accent.opacity(0.6))
                        .frame(width: proxy.size.width * 0.25)
                        .offset(x: sweep ? proxy.size.width * 0.75 : 0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: sweep)
                        .onAppear { sweep = true }
                }
            }
        }
        .frame(height: 8)
    }
}
