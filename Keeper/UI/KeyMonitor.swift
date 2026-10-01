import AppKit
import SwiftUI

/// The whole review runs on the keyboard. A local event monitor sees keys before any view, so
/// focus never gets in the way. Keys typed into a text field or a sheet pass through.
struct KeyMonitor: ViewModifier {
    let library: Library
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    nonisolated(unsafe) let key = event
                    let handled = MainActor.assumeIsolated { handle(key) }
                    return handled ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.window?.isSheet == true || event.window?.firstResponder is NSText || library.askingForPhotos { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if command {
            switch key {
            case "a": library.selectAll()
            case "z": library.undo()
            case "\u{8}", "\u{7f}": library.deleteTargets()
            default: return false
            }
            return true
        }
        guard flags.subtracting([.shift, .numericPad, .function]).isEmpty else { return false }

        switch event.keyCode {
        case 123, 126: library.move(by: -1, extend: shift)
        case 124, 125: library.move(by: 1, extend: shift)
        case 115: library.jump(toEnd: false)
        case 119: library.jump(toEnd: true)
        case 51, 117: library.deleteTargets()
        case 53:
            if library.zoomed { library.zoomed = false } else { library.clearSelection() }
        default:
            switch key {
            case "r": library.rotate(clockwise: !shift)
            case "z", " ": library.zoomed.toggle()
            case "f": library.filter = library.filter == .all ? .flagged : .all
            case "p":
                guard !library.targets.isEmpty else { break }
                if shift { library.askingForPhotos = true } else { library.addToPhotos(album: nil) }
            default: return false
            }
        }
        return true
    }
}
