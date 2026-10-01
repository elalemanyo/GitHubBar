import AppKit
import SwiftUI

struct ItemRow: View {
    let item: FeedItem
    let isNew: Bool
    var isSelected = false
    let onOpen: () -> Void
    /// Set for notifications only.
    let onMarkRead: (() -> Void)?
    let onMarkDone: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Octicon(name: item.kind.icon)
                .foregroundStyle(item.kind.color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(repositoryLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Primer.fgMuted)
                    .lineLimit(1)

                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Primer.fgDefault)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(metaLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Primer.fgMuted)
                        .lineLimit(1)
                    if let review = item.reviewDecision?.label {
                        PrimerLabel(text: review.text, color: review.color)
                    }
                }
            }

            Spacer(minLength: 4)

            if isHovering || isSelected, let onMarkRead, let onMarkDone {
                HStack(spacing: 0) {
                    IconButton(icon: "read", help: "Mark as read · ⇧I", action: onMarkRead)
                    IconButton(icon: "check", help: "Done · E", action: onMarkDone)
                }
                .padding(.vertical, -4)
            } else {
                trailingIndicators
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Primer.accentFg.opacity(0.1) : isHovering ? Primer.rowHover : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Primer.accentFg).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("Open in Browser", action: onOpen)
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
            }
            if let onMarkRead, let onMarkDone {
                Divider()
                Button("Mark as Read", action: onMarkRead)
                Button("Mark as Done", action: onMarkDone)
            }
        }
    }

    private var trailingIndicators: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let status = item.checkStatus {
                Octicon(name: status.icon)
                    .foregroundStyle(status.color)
                    .help(status.help)
            }
            if isNew {
                Circle()
                    .fill(Primer.accentFg)
                    .frame(width: 8, height: 8)
                    .help("New since you last looked")
            }
        }
        .padding(.top, 2)
    }

    private var repositoryLine: String {
        item.number.map { "\(item.repository) #\($0)" } ?? item.repository
    }

    private var metaLine: String {
        let time = Self.relativeFormatter.localizedString(for: item.updatedAt, relativeTo: Date())
        return [item.detail, item.author, time].compactMap { $0 }.joined(separator: " · ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

// MARK: - Primer styling per state

extension FeedItem.Kind {
    var icon: String {
        switch self {
        case .pullRequest(.draft): "git-pull-request-draft"
        case .pullRequest(.merged): "git-merge"
        case .pullRequest(.closed): "git-pull-request-closed"
        case .pullRequest: "git-pull-request"
        case .issue(.closed): "issue-closed"
        case .issue(.notPlanned): "skip"
        case .issue: "issue-opened"
        case .release: "tag"
        case .discussion: "comment"
        case .checkSuite: "workflow"
        case .commit: "git-commit"
        case .securityAlert: "shield"
        case .other: "bell"
        }
    }

    var color: Color {
        switch self {
        case .pullRequest(.open), .issue(.open): Primer.successFg
        case .pullRequest(.merged), .issue(.closed): Primer.doneFg
        case .pullRequest(.closed): Primer.dangerFg
        case .securityAlert: Primer.dangerFg
        default: Primer.fgMuted
        }
    }
}

extension FeedItem.CheckStatus {
    var icon: String {
        switch self {
        case .success: "check"
        case .failure: "x-circle"
        case .pending: "dot-fill"
        }
    }

    var color: Color {
        switch self {
        case .success: Primer.successFg
        case .failure: Primer.dangerFg
        case .pending: Primer.attentionFg
        }
    }

    var help: String {
        switch self {
        case .success: "All checks passed"
        case .failure: "Some checks failed"
        case .pending: "Checks in progress"
        }
    }
}

extension FeedItem.ReviewDecision {
    var label: (text: String, color: Color)? {
        switch self {
        case .approved: ("Approved", Primer.successFg)
        case .changesRequested: ("Changes requested", Primer.dangerFg)
        case .reviewRequired: nil
        }
    }
}
