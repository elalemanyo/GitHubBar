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
            StatusItem.togglePopover()
        }
    }
}
