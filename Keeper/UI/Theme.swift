import AppKit
import SwiftUI

/// Pacer's calm: warm paper in light mode, neutral gray in dark, big tightly tracked type. Keeper's
/// color is golden hour, the orange of the photo you keep. Red is only for deleting and for flags.
enum Theme {
    static var appIcon: NSImage { NSImage(named: "AppIcon") ?? NSApp.applicationIconImage }

    static let canvas = Color(light: 0xF7F5F3, dark: 0x141414)
    static let card = Color(light: 0xFFFFFF, dark: 0x212020)
    static let ink = Color(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let muted = Color(light: 0x85807B, dark: 0xA39E99)
    static let hairline = Color(light: 0xE4E1DD, dark: 0x323131)
    static let hot = Color(light: 0xD92D20, dark: 0xFF6B5E)
    static let accent = Color(light: 0xF06418, dark: 0xFF8A3D)
    static let accentSoft = Color(light: 0xFFB020, dark: 0xFFB84D)
    static let quietWash = Color.primary.opacity(0.07)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// "Keeper" with a golden dot, the way Pacer and Redpen end with theirs.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        let dot = size * 0.3
        HStack(alignment: .firstTextBaseline, spacing: size * 0.3) {
            Text("Keeper").display(size).foregroundStyle(.primary)
            Circle().fill(LinearGradient(colors: [Theme.accentSoft, Theme.accent], startPoint: .top, endPoint: .bottom))
                .frame(width: dot, height: dot)
                .background(Circle().fill(Theme.accent.opacity(0.25)).frame(width: dot * 1.9, height: dot * 1.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keeper")
    }
}

/// Primary and secondary buttons in the calm style.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var tint = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? .white : Theme.ink)
            .background(prominent ? tint : Theme.quietWash, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 30
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(hovering ? Theme.quietWash : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A key cap in the shortcut legend.
struct KeyCap: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Theme.quietWash, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
    }
}

extension View {
    func display(_ size: CGFloat) -> some View {
        font(Theme.display(size)).tracking(-size * 0.035)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Format {
    static func count(_ n: Int, _ noun: String = "photo") -> String {
        "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")"
    }

    static func shot(_ date: Date) -> String {
        guard date != .distantPast else { return "No date" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// "About 2 min left", once there's enough to go on.
    static func remaining(done: Int, total: Int, since start: Date, now: Date = Date()) -> String? {
        let elapsed = now.timeIntervalSince(start)
        guard done >= 8, elapsed > 2, total > done else { return nil }
        let seconds = elapsed / Double(done) * Double(total - done)
        if seconds < 60 { return "Less than a minute left" }
        return "About \(Int((seconds / 60).rounded())) min left"
    }
}
