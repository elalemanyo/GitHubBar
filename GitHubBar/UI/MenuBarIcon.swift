import AppKit
import SwiftUI

/// The status item icon: a template image normally, tinted GitHub blue when something needs attention.
struct MenuBarIcon: View {
    let needsAttention: Bool

    private var appearance: MenuBarAppearance { .shared }

    var body: some View {
        Image(nsImage: image)
            .onAppear { appearance.start() }
    }

    private var image: NSImage {
        guard needsAttention else { return Self.normal }
        return appearance.isDark ? Self.attentionDark : Self.attentionLight
    }

    private static let normal: NSImage = {
        let image = (NSImage(named: "mark-github")?.copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()

    private static let attentionLight: NSImage = normal.tinted(with: Primer.menuBarAttentionLight)
    private static let attentionDark: NSImage = normal.tinted(with: Primer.menuBarAttentionDark)
}
