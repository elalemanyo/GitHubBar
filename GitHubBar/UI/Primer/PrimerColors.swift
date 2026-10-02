import AppKit
import SwiftUI

/// Primer functional color tokens (https://primer.style/foundations/color) for light and dark mode.
enum Primer {
    static let fgDefault = Color(light: 0x1F2328, dark: 0xF0F6FC)
    static let fgMuted = Color(light: 0x59636E, dark: 0x9198A1)
    static let fgOnEmphasis = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

    static let canvasDefault = Color(light: 0xFFFFFF, dark: 0x0D1117)
    static let canvasSubtle = Color(light: 0xF6F8FA, dark: 0x151B23)

    static let borderDefault = Color(light: 0xD1D9E0, dark: 0x3D444D)
    static let borderMuted = Color(light: 0xD1D9E0, lightAlpha: 0.7, dark: 0x3D444D, darkAlpha: 0.7)

    static let accentFg = Color(light: 0x0969DA, dark: 0x4493F8)
    static let accentEmphasis = Color(light: 0x0969DA, dark: 0x1F6FEB)
    static let successFg = Color(light: 0x1A7F37, dark: 0x3FB950)
    static let attentionFg = Color(light: 0x9A6700, dark: 0xD29922)
    static let severeFg = Color(light: 0xBC4C00, dark: 0xDB6D28)
    static let dangerFg = Color(light: 0xD1242F, dark: 0xF85149)
    static let doneFg = Color(light: 0x8250DF, dark: 0xAB7DF8)

    /// Background of `Counter` and neutral labels.
    static let neutralMuted = Color(light: 0x818B98, lightAlpha: 0.2, dark: 0x656C76, darkAlpha: 0.2)
    /// Row hover background (`control.transparent.bgHover`).
    static let rowHover = Color(light: 0x818B98, lightAlpha: 0.1, dark: 0x656C76, darkAlpha: 0.2)

    /// Menu bar tint when something needs attention: Primer's `accent.fg` for a light and a dark menu bar.
    /// Picked by `MenuBarAppearance`, since the menu bar can be dark while the app is light (and vice versa).
    static let menuBarAttentionLight = NSColor(hex: 0x0969DA)
    static let menuBarAttentionDark = NSColor(hex: 0x4493F8)
}

extension Color {
    init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
