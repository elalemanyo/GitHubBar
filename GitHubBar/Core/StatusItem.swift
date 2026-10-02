import AppKit
import Observation

/// Access to the status item button and popover window that `MenuBarExtra` creates but doesn't expose.
@MainActor
enum StatusItem {
    /// Set by the popover view once it's in a window.
    static weak var popoverWindow: NSWindow?

    static var isPopoverOpen: Bool { popoverWindow?.isVisible ?? false }

    /// `MenuBarExtra` has no API to open or close it, so click its status item button,
    /// which also keeps its internal state in sync.
    static func togglePopover() {
        guard let button = button() else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    static func closePopover() {
        guard isPopoverOpen else { return }
        if let button = button() {
            button.performClick(nil)
        } else {
            popoverWindow?.close()
        }
    }

    /// Opens a URL in its default app. In the foreground the popover closes so focus moves there;
    /// in the background (⌘-click) the popover stays open for triaging several items.
    static func open(_ url: URL, inBackground: Bool = false) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !inBackground
        NSWorkspace.shared.open(url, configuration: configuration)
        if !inBackground { closePopover() }
    }

    static func button() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = findButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}

/// Whether the menu bar is currently dark. That depends on dark mode and, in light mode, on the
/// wallpaper behind the translucent menu bar, so it's read from the status item button itself.
@MainActor
@Observable
final class MenuBarAppearance {
    static let shared = MenuBarAppearance()

    private(set) var isDark = false

    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {}

    /// Starts observing the status item button. It only exists once `MenuBarExtra` is on screen,
    /// so retry briefly until it shows up.
    func start(attempt: Int = 0) {
        guard observation == nil else { return }
        guard let button = StatusItem.button() else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.start(attempt: attempt + 1)
                }
            }
            return
        }
        observation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] button, _ in
            let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            Task { @MainActor in self?.isDark = isDark }
        }
    }
}
