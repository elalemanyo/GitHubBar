import AppKit
import Observation
import Sparkle

/// Wraps Sparkle's updater. Stays inactive in builds without a public signing key (local dev builds).
///
/// Scheduled updates use Sparkle's "gentle reminders": instead of an alert popping up behind other apps
/// (this is a menu bar app, rarely in front), the popover shows a banner and Sparkle's window only
/// opens when the user clicks Install. https://sparkle-project.org/documentation/gentle-reminders
@MainActor
@Observable
final class Updater: NSObject {
    static let shared = Updater()

    /// Whether this build has a Sparkle public key, i.e. can verify and install updates.
    let isConfigured: Bool
    private(set) var canCheckForUpdates = false
    /// Version of a found update the user hasn't looked at yet; drives the popover banner.
    private(set) var availableVersion: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private static let notifiedVersionKey = "notifiedUpdateVersion"

    private override init() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !publicKey.isEmpty
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: isConfigured, updaterDelegate: nil, userDriverDelegate: self)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Checks for updates, or brings an already found update into focus.
    func checkForUpdates() {
        StatusItem.closePopover()
        // Menu bar apps aren't active by default; bring Sparkle's window to the front.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// e.g. "0.0.1 (3)".
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    #if DEBUG
    /// Shows the update banner without Sparkle, for screenshots.
    func showPreviewUpdate(_ version: String?) {
        availableVersion = version
    }
    #endif
}

// Sparkle's delegate protocol predates Swift concurrency; it's always called on the main thread.
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle show the alert only when it would get immediate focus (e.g. right after launch);
    /// otherwise we show the banner.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        availableVersion = version

        // One quiet notification per version, and only if notifications are already allowed for tabs.
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.notifiedVersionKey) != version else { return }
        defaults.set(version, forKey: Self.notifiedVersionKey)
        SystemNotifier.shared.postUpdateAvailable(version: version)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
