import Foundation

/// A notification thread as returned by `GET /notifications`.
struct GitHubNotification: Decodable, Hashable, Identifiable {
    struct Subject: Decodable, Hashable {
        let title: String
        let url: URL?
        let type: String
    }

    struct Repository: Decodable, Hashable {
        struct Owner: Decodable, Hashable { let login: String }
        let fullName: String
        let htmlUrl: URL
        let owner: Owner
    }

    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository
}

extension GitHubNotification {
    /// The number of the issue or pull request, if the subject is one.
    var number: Int? {
        guard let url = subject.url, ["Issue", "PullRequest"].contains(subject.type) else { return nil }
        return Int(url.lastPathComponent)
    }

    /// Reference for looking up the issue or pull request's current state.
    var subjectRef: GitHubClient.SubjectRef? {
        guard let number else { return nil }
        let parts = repository.fullName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return GitHubClient.SubjectRef(owner: String(parts[0]), name: String(parts[1]), number: number)
    }

    /// The subject's API URL rewritten as a github.com URL.
    var htmlURL: URL {
        let repo = repository.htmlUrl
        guard let apiURL = subject.url else {
            switch subject.type {
            case "CheckSuite": return repo.appendingPathComponent("actions")
            case "Discussion": return repo.appendingPathComponent("discussions")
            default: return repo
            }
        }

        // e.g. https://api.github.com/repos/owner/name/pulls/12 -> https://github.com/owner/name/pull/12
        let parts = apiURL.pathComponents
        guard let reposIndex = parts.firstIndex(of: "repos"), parts.count > reposIndex + 4 else { return repo }
        let resource = parts[reposIndex + 3]
        let identifier = parts[reposIndex + 4]
        switch resource {
        case "pulls": return repo.appendingPathComponent("pull/\(identifier)")
        case "issues": return repo.appendingPathComponent("issues/\(identifier)")
        case "commits": return repo.appendingPathComponent("commit/\(identifier)")
        case "releases": return repo.appendingPathComponent("releases")
        case "discussions": return repo.appendingPathComponent("discussions/\(identifier)")
        default: return repo
        }
    }

    var reasonLabel: String {
        switch reason {
        case "review_requested": "Review requested"
        case "mention": "Mentioned"
        case "team_mention": "Team mentioned"
        case "assign": "Assigned"
        case "author": "Author"
        case "comment": "Comment"
        case "ci_activity": "CI activity"
        case "state_change": "State change"
        case "security_alert": "Security alert"
        case "subscribed": "Subscribed"
        case "manual": "Subscribed"
        case "invitation": "Invitation"
        case "approval_requested": "Approval requested"
        default: reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The row for this notification, using `subject` (from `GitHubClient.lookUp`) for state, CI and review.
    func feedItem(subject details: FeedItem?) -> FeedItem {
        var item = feedItem
        if let details {
            item.kind = details.kind
            item.author = details.author
            item.checkStatus = details.checkStatus
            item.reviewDecision = details.reviewDecision
        }
        return item
    }

    var feedItem: FeedItem {
        let kind: FeedItem.Kind = switch subject.type {
        case "PullRequest": .pullRequest(.unknown)
        case "Issue": .issue(.unknown)
        case "Release": .release
        case "Discussion": .discussion
        case "CheckSuite": .checkSuite
        case "Commit": .commit
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread": .securityAlert
        default: .other
        }

        return FeedItem(
            id: "notification-\(id)",
            kind: kind,
            title: subject.title,
            repository: repository.fullName,
            number: number,
            url: htmlURL,
            updatedAt: updatedAt,
            author: nil,
            detail: reasonLabel,
            isUnread: unread,
            notificationThreadID: id
        )
    }
}
