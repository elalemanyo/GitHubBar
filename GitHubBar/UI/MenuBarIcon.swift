import AppKit
import SwiftUI

/// The status item icon: a template image normally, tinted when something needs attention.
struct MenuBarIcon: View {
    let needsAttention: Bool

    var body: some View {
        Image(nsImage: needsAttention ? Self.attention : Self.normal)
    }

    private static let normal: NSImage = {
        let image = (NSImage(named: "mark-github")?.copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()

    private static let attention: NSImage = normal.tinted(with: Primer.menuBarAttention)
}
