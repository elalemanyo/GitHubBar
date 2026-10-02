#if DEBUG
import AppKit
import CoreImage
import KeyboardShortcuts
import SwiftUI

/// Debug helper: `GitHubBar --preview <folder>` renders the website and README screenshots from the
/// real views with `DemoData`, in light and dark, then quits. Run it through scripts/make-screenshots.sh.
@MainActor
enum PreviewRenderer {
    static var requestedFolder: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    enum Theme: String, CaseIterable {
        case light, dark

        var appearance: NSAppearance { NSAppearance(named: self == .light ? .aqua : .darkAqua)! }
        var isDark: Bool { self == .dark }
    }

    static func run(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Show a global shortcut in the Account pane; cleared again below.
        KeyboardShortcuts.setShortcut(.init(.g, modifiers: [.option, .command]), for: .togglePopover)

        for theme in Theme.allCases {
            NSApp.appearance = theme.appearance
            func save(_ rep: NSBitmapImageRep, _ name: String) {
                let url = folder.appendingPathComponent("\(name)-\(theme.rawValue).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }

            let inbox = DemoData.makeState(selectedTab: DemoData.inbox)
            save(hero(inbox, theme: theme), "hero")
            save(popoverCard(inbox, selectedItemID: "n1", theme: theme), "popover-inbox")
            save(popoverCard(DemoData.makeState(selectedTab: DemoData.reviews), theme: theme), "popover-reviews")
            save(popoverCard(DemoData.makeState(selectedTab: DemoData.mine), theme: theme), "popover-mine")
            save(popoverCard(inbox, showShortcuts: true, theme: theme), "popover-shortcuts")

            Updater.shared.showPreviewUpdate("0.1.0")
            save(popoverCard(DemoData.makeState(selectedTab: DemoData.reviews), theme: theme), "popover-update")
            Updater.shared.showPreviewUpdate(nil)

            save(settingsCard(tab: "Account", theme: theme) { AccountSettings() }, "settings-account")
            save(settingsCard(tab: "Tabs", theme: theme) {
                TabsSettings(selection: DemoData.reviews.id, editorMessage: "Prompt copied. Paste it into your AI assistant.")
            }, "settings-tabs-search")
            save(settingsCard(tab: "Tabs", theme: theme) {
                TabsSettings(selection: DemoData.work.id, editorMessage: "5 of 6 unread notifications")
            }, "settings-tabs-notifications")

            save(menuBarStrip(theme: theme), "menubar")
            save(notificationScene(theme: theme), "notification")
        }

        NSApp.appearance = nil
        if let themes = themesSideBySide() {
            try? themes.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("themes.png"))
        }

        KeyboardShortcuts.setShortcut(nil, for: .togglePopover)
        print("Screenshots written to \(folder.path)")
        exit(0)
    }

    // MARK: - Scenes

    /// Same proportions as the README cover (1200×630).
    private static let heroSize = NSSize(width: 1280, height: 672)
    private static let menuBarHeight: CGFloat = 30
    private static let popoverSize = NSSize(width: 400, height: 520)
    fileprivate static let settingsHeight: CGFloat = 540

    /// Desktop with the menu bar, the lit GitHubBar icon and the open popover.
    private static func hero(_ state: AppState, theme: Theme) -> NSBitmapImageRep {
        let popover = snapshot(PopoverView().environment(state), size: popoverSize, theme: theme)
        let wallpaper = wallpaper(size: heroSize, theme: theme)
        let iconX: CGFloat = 760

        return canvas(size: heroSize, theme: theme) { bounds in
            wallpaper.draw(in: bounds)
            drawMenuBar(in: NSRect(x: 0, y: bounds.maxY - menuBarHeight, width: bounds.width, height: menuBarHeight),
                        iconX: iconX, lit: true, theme: theme)
            let frame = NSRect(x: iconX - popoverSize.width / 2, y: bounds.maxY - menuBarHeight - 8 - popoverSize.height,
                               width: popoverSize.width, height: popoverSize.height)
            drawCard(popover, in: frame, radius: 12, theme: theme)
        }
    }

    /// The popover alone with a soft shadow on a transparent background.
    private static func popoverCard(_ state: AppState, selectedItemID: String? = nil, showShortcuts: Bool = false,
                                    theme: Theme) -> NSBitmapImageRep {
        let image = snapshot(PopoverView(selectedItemID: selectedItemID, showShortcuts: showShortcuts).environment(state),
                             size: popoverSize, theme: theme)
        return card(image, radius: 12, theme: theme)
    }

    /// The same popover in light and dark next to each other.
    private static func themesSideBySide() -> NSBitmapImageRep? {
        let gap: CGFloat = 32, padding: CGFloat = 40
        let size = NSSize(width: popoverSize.width * 2 + gap + padding * 2, height: popoverSize.height + padding * 2)
        let images = Theme.allCases.map { theme in
            (theme, snapshot(PopoverView().environment(DemoData.makeState(selectedTab: DemoData.mine)), size: popoverSize, theme: theme))
        }
        return canvas(size: size, theme: .light) { bounds in
            for (index, (theme, image)) in images.enumerated() {
                let frame = NSRect(x: padding + CGFloat(index) * (popoverSize.width + gap), y: padding,
                                   width: popoverSize.width, height: popoverSize.height)
                theme.appearance.performAsCurrentDrawingAppearance {
                    drawCard(image, in: frame, radius: 12, theme: theme)
                }
            }
        }
    }

    /// A Settings pane inside a drawn window frame.
    private static func settingsCard(tab: String, theme: Theme, @ViewBuilder content: () -> some View) -> NSBitmapImageRep {
        let state = DemoData.makeState(includeWork: true)
        // A bit taller than the real window (460) so the whole tab editor fits.
        let size = NSSize(width: 680, height: settingsHeight + 57)
        let image = snapshot(SettingsWindowFrame(selected: tab) { content() }.environment(state), size: size, theme: theme)
        return card(image, radius: 12, theme: theme)
    }

    /// The right half of a menu bar with the highlighted icon.
    private static func menuBarStrip(theme: Theme) -> NSBitmapImageRep {
        let size = NSSize(width: 560, height: 90)
        let wallpaper = wallpaper(size: NSSize(width: 1280, height: 800), theme: theme)
        return canvas(size: size, theme: theme) { bounds in
            wallpaper.draw(in: bounds, from: NSRect(x: 720, y: 800 - size.height, width: size.width, height: size.height),
                           operation: .copy, fraction: 1)
            drawMenuBar(in: NSRect(x: -720, y: bounds.maxY - menuBarHeight, width: 1280, height: menuBarHeight),
                        iconX: 760, lit: true, theme: theme, showAppMenus: false)
        }
    }

    /// A macOS notification banner for a new review request.
    private static func notificationScene(theme: Theme) -> NSBitmapImageRep {
        let size = NSSize(width: 560, height: 190)
        let wallpaper = wallpaper(size: NSSize(width: 1280, height: 800), theme: theme)
        return canvas(size: size, theme: theme) { bounds in
            wallpaper.draw(in: bounds, from: NSRect(x: 720, y: 610, width: size.width, height: size.height),
                           operation: .copy, fraction: 1)
            drawMenuBar(in: NSRect(x: -720, y: bounds.maxY - menuBarHeight, width: 1280, height: menuBarHeight),
                        iconX: 760, lit: true, theme: theme, showAppMenus: false)
            let banner = NSRect(x: bounds.maxX - 16 - 360, y: bounds.maxY - menuBarHeight - 12 - 84, width: 360, height: 84)
            drawNotification(in: banner, theme: theme)
        }
    }

    // MARK: - Drawing

    private static func drawMenuBar(in rect: NSRect, iconX: CGFloat, lit: Bool, theme: Theme, showAppMenus: Bool = true) {
        (theme.isDark ? NSColor.black.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.55)).setFill()
        rect.fill()

        let text = theme.isDark ? NSColor.white : NSColor.black
        let midY = rect.midY

        if showAppMenus {
            var x = rect.minX + 20
            for (index, title) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
                let font = NSFont.systemFont(ofSize: 13, weight: index == 0 ? .bold : .regular)
                let string = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: text])
                string.draw(at: NSPoint(x: x, y: midY - string.size().height / 2))
                x += string.size().width + 20
            }
        }

        // GitHubBar's icon, then a few system items and the clock to its right.
        let mark = NSImage(named: "mark-github")!
        let icon = lit
            ? mark.tinted(with: theme.isDark ? Primer.menuBarAttentionDark : Primer.menuBarAttentionLight)
            : mark.tinted(with: text)
        icon.draw(in: NSRect(x: rect.minX + iconX - 8, y: midY - 8, width: 16, height: 16))

        var x = rect.minX + iconX + 30
        for symbol in ["battery.75percent", "wifi", "magnifyingglass", "switch.2"] {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)?.tinted(with: text) else { continue }
            image.draw(in: NSRect(x: x, y: midY - image.size.height / 2, width: image.size.width, height: image.size.height))
            x += image.size.width + 18
        }
        let clock = NSAttributedString(string: "Fri 2 Oct  9:41",
                                       attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: text])
        clock.draw(at: NSPoint(x: x + 4, y: midY - clock.size().height / 2))
    }

    private static func drawNotification(in rect: NSRect, theme: Theme) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(theme.isDark ? 0.5 : 0.18)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        (theme.isDark ? NSColor(white: 0.17, alpha: 0.96) : NSColor(white: 0.98, alpha: 0.96)).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let primary = theme.isDark ? NSColor.white : NSColor.black
        let secondary = primary.withAlphaComponent(0.6)
        NSApp.applicationIconImage.draw(in: NSRect(x: rect.minX + 12, y: rect.midY - 19, width: 38, height: 38))

        let left = rect.minX + 60
        func line(_ string: String, _ font: NSFont, _ color: NSColor, top: CGFloat) {
            let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
            text.draw(at: NSPoint(x: left, y: rect.maxY - top - text.size().height))
        }
        line("Reviews", .systemFont(ofSize: 13, weight: .semibold), primary, top: 12)
        line("acme/web #482", .systemFont(ofSize: 13), primary, top: 30)
        line("Fix login redirect for SSO users", .systemFont(ofSize: 13), secondary, top: 48)
        let now = NSAttributedString(string: "now", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondary])
        now.draw(at: NSPoint(x: rect.maxX - 14 - now.size().width, y: rect.maxY - 12 - now.size().height))
    }

    /// Draws a rounded image with a shadow and a hairline border, like a floating window.
    private static func drawCard(_ image: NSImage, in frame: NSRect, radius: CGFloat, theme: Theme) {
        let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(theme.isDark ? 0.55 : 0.22)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        (theme.isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.12)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// A card on a transparent canvas with room for its shadow.
    private static func card(_ image: NSImage, radius: CGFloat, theme: Theme) -> NSBitmapImageRep {
        let padding: CGFloat = 40
        let size = NSSize(width: image.size.width + padding * 2, height: image.size.height + padding * 2)
        return canvas(size: size, theme: theme) { bounds in
            drawCard(image, in: bounds.insetBy(dx: padding, dy: padding), radius: radius, theme: theme)
        }
    }

    /// Soft, blurred shapes in the colors of the README cover.
    private static func wallpaper(size: NSSize, theme: Theme) -> NSImage {
        let base = canvas(size: size, theme: theme) { bounds in
            let top = theme.isDark ? NSColor(srgbRed: 0.10, green: 0.07, blue: 0.24, alpha: 1)
                                   : NSColor(srgbRed: 0.80, green: 0.74, blue: 1.00, alpha: 1)
            let bottom = theme.isDark ? NSColor(srgbRed: 0.05, green: 0.07, blue: 0.13, alpha: 1)
                                      : NSColor(srgbRed: 1.00, green: 0.86, blue: 0.93, alpha: 1)
            NSGradient(starting: bottom, ending: top)!.draw(in: bounds, angle: 90)

            let alpha: CGFloat = theme.isDark ? 0.45 : 0.75
            let blobs: [(NSColor, NSRect)] = [
                (NSColor(srgbRed: 0.43, green: 0.26, blue: 0.79, alpha: alpha), NSRect(x: -120, y: 380, width: 620, height: 620)),
                (NSColor(srgbRed: 0.24, green: 0.86, blue: 0.59, alpha: alpha * 0.8), NSRect(x: 980, y: -160, width: 520, height: 520)),
                (NSColor(srgbRed: 1.00, green: 0.78, blue: 0.24, alpha: alpha * 0.8), NSRect(x: 820, y: 420, width: 440, height: 440)),
                (NSColor(srgbRed: 0.97, green: 0.47, blue: 0.73, alpha: alpha * 0.7), NSRect(x: 220, y: -200, width: 560, height: 560)),
            ]
            for (color, rect) in blobs {
                color.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
        }

        let input = CIImage(bitmapImageRep: base)!
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 120).cropped(to: input.extent)
        let cgImage = CIContext().createCGImage(blurred, from: input.extent)!
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - Rendering

    /// Renders a SwiftUI view at 2x through a hidden window, like it appears on screen.
    private static func snapshot(_ view: some View, size: NSSize, theme: Theme) -> NSImage {
        let hosting = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(\.controlActiveState, .key))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = theme.appearance
        // A key window off-screen, so controls render active (blue toggles and selections) without
        // anything flashing on the display.
        let window = CaptureWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = theme.appearance
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<15 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: .now + 0.05)
        }

        let rep = bitmap(size: size)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func canvas(size: NSSize, theme: Theme, draw: (NSRect) -> Void) -> NSBitmapImageRep {
        let rep = bitmap(size: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        theme.appearance.performAsCurrentDrawingAppearance {
            draw(NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func bitmap(size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        return rep
    }

}

/// Reports itself as the active window, so controls draw in their active style (blue toggles and selections).
private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// A Settings window's title bar and toolbar around a pane, for screenshots.
private struct SettingsWindowFrame<Content: View>: View {
    let selected: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([NSColor.systemRed, .systemYellow, .systemGreen], id: \.self) { color in
                        Circle().fill(Color(nsColor: color)).frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                .padding(.leading, 16)

                HStack(spacing: 4) {
                    toolbarItem("Account", symbol: "person.crop.circle")
                    toolbarItem("Tabs", symbol: "square.stack")
                }
            }
            .frame(height: 56)
            Divider()
            content
                .frame(width: 680, height: PreviewRenderer.settingsHeight)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func toolbarItem(_ title: String, symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 17))
            Text(title).font(.system(size: 11))
        }
        .foregroundStyle(title == selected ? Color.accentColor : Color.secondary)
        .frame(width: 64, height: 46)
        .background(RoundedRectangle(cornerRadius: 6).fill(title == selected ? Color.primary.opacity(0.07) : .clear))
    }
}
#endif
