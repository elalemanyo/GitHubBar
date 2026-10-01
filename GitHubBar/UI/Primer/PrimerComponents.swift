import SwiftUI

/// Primer `CounterLabel`.
struct CounterLabel: View {
    let count: Int
    var emphasized = false

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(emphasized ? Primer.fgOnEmphasis : Primer.fgDefault)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(Capsule().fill(emphasized ? Primer.accentEmphasis : Primer.neutralMuted))
    }
}

/// Primer `Label` (outlined pill).
struct PrimerLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color, lineWidth: 1))
    }
}

/// Primer `Flash` banner.
struct FlashBanner: View {
    enum Variant { case attention, danger }

    let message: String
    var variant: Variant = .attention

    var body: some View {
        let color = variant == .danger ? Primer.dangerFg : Primer.attentionFg
        HStack(alignment: .top, spacing: 8) {
            Octicon(name: variant == .danger ? "stop" : "alert")
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Primer.fgDefault)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.4), lineWidth: 1))
    }
}

/// Borderless icon button, like Primer's `IconButton` with the invisible variant.
struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Octicon(name: icon)
                .foregroundStyle(Primer.fgMuted)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Primer.rowHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// Primer-style blank slate for empty and error states.
struct BlankSlate<Actions: View>: View {
    let icon: String
    let title: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 8) {
            Octicon(name: icon, size: 24)
                .foregroundStyle(Primer.fgMuted)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Primer.fgDefault)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Primer.fgMuted)
                    .multilineTextAlignment(.center)
            }
            actions()
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension BlankSlate where Actions == EmptyView {
    init(icon: String, title: String, message: String? = nil) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}
