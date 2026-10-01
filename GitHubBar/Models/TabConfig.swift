import Foundation

/// Where a tab's items come from.
enum TabSource: String, Codable, CaseIterable, Identifiable {
    /// GitHub search (issues & pull requests) via GraphQL. Query uses github.com search syntax.
    case search
    /// Unread notifications via REST, filtered locally with `NotificationFilter` syntax.
    case notifications

    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: "Search"
        case .notifications: "Notifications"
        }
    }
}

/// When a tab should light up the menu bar icon.
enum AttentionRule: String, Codable, CaseIterable, Identifiable {
    case never
    /// Any result at all (e.g. review requests, unread notifications).
    case anyItems
    /// Only items that appeared since the tab was last viewed.
    case newItems

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "Never"
        case .anyItems: "When it has items"
        case .newItems: "When new items appear"
        }
    }
}

struct TabConfig: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var icon: String
    var source: TabSource
    var query: String
    var attention: AttentionRule
    var isEnabled: Bool
    /// Post a macOS notification when new items appear.
    var notify: Bool

    init(id: UUID = UUID(), title: String, icon: String, source: TabSource, query: String,
         attention: AttentionRule, isEnabled: Bool = true, notify: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.source = source
        self.query = query
        self.attention = attention
        self.isEnabled = isEnabled
        self.notify = notify
    }

    /// Tolerates missing keys so tabs saved by older versions (or hand-edited exports) still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "filter"
        source = try container.decodeIfPresent(TabSource.self, forKey: .source) ?? .search
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        attention = try container.decodeIfPresent(AttentionRule.self, forKey: .attention) ?? .never
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        notify = try container.decodeIfPresent(Bool.self, forKey: .notify) ?? false
    }

    var requestSignature: String { "\(source.rawValue)|\(query)" }

    /// Link to the same results on github.com.
    var webURL: URL {
        switch source {
        case .notifications:
            return URL(string: "https://github.com/notifications")!
        case .search:
            var components = URLComponents(string: "https://github.com/issues")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            return components.url!
        }
    }
}

struct TabPreset: Identifiable {
    let title: String
    let icon: String
    let source: TabSource
    let query: String
    let attention: AttentionRule

    var id: String { title }

    func makeTab() -> TabConfig {
        TabConfig(title: title, icon: icon, source: source, query: query, attention: attention)
    }
}

extension TabPreset {
    static let notifications: [TabPreset] = [
        TabPreset(title: "Inbox", icon: "bell", source: .notifications,
                  query: "", attention: .anyItems),
        TabPreset(title: "Mentions", icon: "mention", source: .notifications,
                  query: "reason:mention,team_mention", attention: .anyItems),
        TabPreset(title: "CI activity", icon: "workflow", source: .notifications,
                  query: "reason:ci_activity", attention: .never),
        TabPreset(title: "Inbox (no noise)", icon: "inbox", source: .notifications,
                  query: "-reason:ci_activity -reason:state_change", attention: .anyItems),
    ]

    static let search: [TabPreset] = [
        TabPreset(title: "Review requests", icon: "code-review", source: .search,
                  query: "is:pr is:open review-requested:@me archived:false", attention: .anyItems),
        TabPreset(title: "My pull requests", icon: "git-pull-request", source: .search,
                  query: "is:pr is:open author:@me archived:false", attention: .never),
        TabPreset(title: "Failing CI", icon: "x-circle", source: .search,
                  query: "is:pr is:open author:@me status:failure archived:false", attention: .anyItems),
        TabPreset(title: "Ready to merge", icon: "git-merge", source: .search,
                  query: "is:pr is:open author:@me review:approved archived:false", attention: .newItems),
        TabPreset(title: "Assigned to me", icon: "person", source: .search,
                  query: "is:open assignee:@me archived:false", attention: .newItems),
        TabPreset(title: "Mentioned", icon: "mention", source: .search,
                  query: "is:open mentions:@me archived:false", attention: .newItems),
    ]

    static let all = notifications + search

    /// Tabs created on first launch.
    static let defaults: [TabConfig] = [
        notifications[0].makeTab(),
        search[0].makeTab(),
        search[1].makeTab(),
    ]
}
