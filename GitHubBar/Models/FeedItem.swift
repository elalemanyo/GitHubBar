import Foundation

/// A single row in a tab, regardless of whether it came from search or notifications.
struct FeedItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case pullRequest(PullRequestState)
        case issue(IssueState)
        case release
        case discussion
        case checkSuite
        case commit
        case securityAlert
        case other
    }

    /// `unknown` is used for notifications, which don't include the subject's state.
    enum PullRequestState: Hashable { case open, draft, merged, closed, unknown }
    enum IssueState: Hashable { case open, closed, notPlanned, unknown }

    enum CheckStatus: Hashable { case success, failure, pending }
    enum ReviewDecision: Hashable { case approved, changesRequested, reviewRequired }

    let id: String
    let kind: Kind
    let title: String
    let repository: String
    let number: Int?
    let url: URL
    let updatedAt: Date
    let author: String?
    /// Short context line, e.g. the notification reason.
    let detail: String?
    var isUnread = false
    var checkStatus: CheckStatus?
    var reviewDecision: ReviewDecision?
    /// Set for notification items so they can be marked as read.
    var notificationThreadID: String?
}

/// The outcome of the latest refresh for one tab.
struct TabResult {
    var items: [FeedItem] = []
    var totalCount = 0
    var error: String?
}
