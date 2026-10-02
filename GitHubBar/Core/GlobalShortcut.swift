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
        guard let button = StatusItem.button() else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    /// Closes the popover by toggling the status item, which keeps `MenuBarExtra`'s state in sync.
    /// Falls back to closing the key window if the button can't be found.
    static func closePopover() {
        if let button = StatusItem.button() {
            button.performClick(nil)
        } else {
            NSApp.keyWindow?.close()
        }
    }
}
