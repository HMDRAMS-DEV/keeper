import AppKit
import Observation
@preconcurrency import Sparkle

/// Sparkle. It reads the appcast on the website once a day. An update
/// found while the app is in front opens Sparkle's window; one found in the background waits in
/// the toolbar instead of stealing focus.
@MainActor @Observable
final class Updater: NSObject {
    static let shared = Updater()

    /// The version a background check found, until the person looks at it.
    private(set) var available: String?

    var automaticallyChecks = true {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
        // Unit tests run inside the app, and shouldn't reach the network.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    /// Checks now, or shows the update a background check already found.
    func check() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { available = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        available = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        available = nil
    }
}
