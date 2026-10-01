import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens or closes the menu bar popover from anywhere. No default; set in Settings.
    static let togglePopover = Self("togglePopover")
}

@MainActor
enum GlobalShortcut {
    static func register() {
        KeyboardShortcuts.onKeyUp(for: .togglePopover) {
            togglePopover()
        }
    }

    /// `MenuBarExtra` has no API to open it programmatically, so click its status item button.
    static func togglePopover() {
        guard let button = statusItemButton() else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    /// Closes the popover by toggling the status item, which keeps `MenuBarExtra`'s state in sync.
    /// Falls back to closing the key window if the button can't be found.
    static func closePopover() {
        if let button = statusItemButton() {
            button.performClick(nil)
        } else {
            NSApp.keyWindow?.close()
        }
    }

    private static func statusItemButton() -> NSStatusBarButton? {
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
