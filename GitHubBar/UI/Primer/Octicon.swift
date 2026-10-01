import AppKit
import SwiftUI

/// An Octicon from the bundled asset catalog (see scripts/update-octicons.sh).
struct Octicon: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        Image(OcticonCatalog.names.contains(name) ? name : "dot-fill")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

extension NSImage {
    /// Returns a non-template copy filled with `color`, keeping the alpha mask.
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}
