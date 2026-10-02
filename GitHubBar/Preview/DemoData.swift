#if DEBUG
import Foundation

/// Invented tabs and items for the screenshots rendered by `PreviewRenderer`.
/// Organizations and people are made up so no real data ends up on the website.
@MainActor
enum DemoData {
    static let viewer = GitHubClient.Viewer(login: "you", scopes: ["notifications", "repo"])

    static let inbox = TabConfig(title: "Inbox", icon: "bell", source: .notifications, query: "",
                                 attention: .anyItems, notify: true)
    static let reviews = TabConfig(title: "Reviews", icon: "code-review", source: .search,
                                   query: "is:pr is:open review-requested:@me archived:false",
                                   attention: .anyItems, notify: true)
    static let mine = TabConfig(title: "My PRs", icon: "git-pull-request", source: .search,
                                query: "is:pr is:open author:@me archived:false", attention: .never)
    static let work = TabConfig(title: "Work", icon: "organization", source: .notifications,
                                query: "org:acme,globex -reason:ci_activity", attention: .newItems)

    /// Three tabs fit the popover's tab bar with titles, like most setups. The "Work" tab only appears in
    /// the Settings screenshots, to show a notification filter.
    static let tabs = [inbox, reviews, mine]

    /// Items with the blue "new" dot.
    static let unseen: Set<String> = ["n1", "n3", "r1"]

    static func makeState(selectedTab: TabConfig? = nil, snoozedUntil: Date? = nil, includeWork: Bool = false) -> AppState {
        let selectedTab = selectedTab ?? inbox
        let state = AppState(isPreview: true)
        let work = notifications.filter { ["acme", "globex"].contains($0.repository.split(separator: "/").first) }
        state.loadPreview(
            tabs: includeWork ? tabs + [Self.work] : tabs,
            results: [
                inbox.id: TabResult(items: notifications, totalCount: notifications.count),
                reviews.id: TabResult(items: reviewRequests, totalCount: reviewRequests.count),
                mine.id: TabResult(items: myPullRequests, totalCount: myPullRequests.count),
                Self.work.id: TabResult(items: work, totalCount: work.count),
            ],
            unseen: unseen,
            selectedTabID: selectedTab.id,
            viewer: viewer,
            snoozedUntil: snoozedUntil
        )
        return state
    }

    // MARK: - Items

    static let notifications: [FeedItem] = [
        item("n1", .pullRequest(.open), "acme/web", 482, "Fix login redirect for SSO users",
             author: "lena", minutes: 3, detail: "Review requested", checks: .success, thread: true),
        item("n2", .pullRequest(.open), "acme/api", 1290, "Rate limit webhooks per installation",
             author: "marco", minutes: 18, detail: "Mentioned", checks: .pending, thread: true),
        item("n3", .issue(.open), "globex/mobile", 77, "App crashes when opening settings on iPad",
             author: "priya", minutes: 42, detail: "Assigned", thread: true),
        item("n4", .pullRequest(.merged), "acme/design-system", 318, "Add dark mode tokens to Button",
             author: "sam", minutes: 95, detail: "Comment", checks: .success, review: .approved, thread: true),
        item("n5", .release, "acme/web", nil, "v2.4.0",
             author: nil, minutes: 180, detail: "Subscribed", thread: true),
        item("n6", .pullRequest(.draft), "initech/infra", 56, "Upgrade Postgres to 16",
             author: "noah", minutes: 260, detail: "Review requested", checks: .failure, thread: true),
    ]

    static let reviewRequests: [FeedItem] = [
        item("r1", .pullRequest(.open), "acme/web", 482, "Fix login redirect for SSO users",
             author: "lena", minutes: 3, checks: .success, review: .reviewRequired),
        item("r2", .pullRequest(.open), "acme/api", 1301, "Cache GraphQL responses for 60 seconds",
             author: "marco", minutes: 64, checks: .pending, review: .reviewRequired),
        item("r3", .pullRequest(.open), "globex/mobile", 81, "Support Dynamic Type in onboarding",
             author: "priya", minutes: 150, checks: .success, review: .approved),
        item("r4", .pullRequest(.open), "acme/design-system", 322, "Deprecate Box in favor of Card",
             author: "sam", minutes: 400, checks: .failure, review: .changesRequested),
    ]

    static let myPullRequests: [FeedItem] = [
        item("m1", .pullRequest(.open), "acme/web", 479, "Add keyboard shortcuts to the inbox",
             author: "you", minutes: 12, checks: .success, review: .approved),
        item("m2", .pullRequest(.open), "acme/api", 1287, "Retry failed deliveries with backoff",
             author: "you", minutes: 75, checks: .failure, review: .changesRequested),
        item("m3", .pullRequest(.draft), "globex/mobile", 80, "Dark mode for home screen widgets",
             author: "you", minutes: 200, checks: .pending),
        item("m4", .pullRequest(.open), "acme/design-system", 320, "Fix focus ring on IconButton",
             author: "you", minutes: 1440, checks: .success, review: .reviewRequired),
        item("m5", .pullRequest(.open), "acme/web", 475, "Upgrade to Node 24",
             author: "you", minutes: 2880, checks: .pending),
    ]

    private static func item(_ id: String, _ kind: FeedItem.Kind, _ repository: String, _ number: Int?,
                             _ title: String, author: String?, minutes: Double, detail: String? = nil,
                             checks: FeedItem.CheckStatus? = nil, review: FeedItem.ReviewDecision? = nil,
                             thread: Bool = false) -> FeedItem {
        FeedItem(
            id: id,
            kind: kind,
            title: title,
            repository: repository,
            number: number,
            url: URL(string: "https://github.com/\(repository)")!,
            updatedAt: Date().addingTimeInterval(-minutes * 60),
            author: author,
            detail: detail,
            isUnread: thread,
            checkStatus: checks,
            reviewDecision: review,
            notificationThreadID: thread ? id : nil
        )
    }
}
#endif
