import Foundation

/// Search-like filter for notification tabs, evaluated locally.
///
///     reason:mention,team_mention -reason:ci_activity type:pr -state:merged,closed repo:owner/name org:owner fix
///
/// - Terms are ANDed; comma-separated values within a term are ORed.
/// - A leading `-` negates a term.
/// - Words without a known qualifier match the subject title (case-insensitive).
struct NotificationFilter {
    struct Term: Equatable {
        enum Field: String, CaseIterable {
            case reason, type, repo, org, state
            case status = "is"
        }

        let field: Field?
        let values: [String]
        let negated: Bool
    }

    static let typeAliases: [String: String] = [
        "pr": "pullrequest",
        "pull": "pullrequest",
        "ci": "checksuite",
    ]

    let terms: [Term]
    /// Tokens that looked like `key:value` but used an unknown key; shown as warnings in the editor.
    let unknownQualifiers: [String]

    init(_ query: String) {
        var terms: [Term] = []
        var unknown: [String] = []

        for rawToken in query.split(whereSeparator: \.isWhitespace) {
            var token = Substring(rawToken)
            let negated = token.hasPrefix("-") && token.count > 1
            if negated { token = token.dropFirst() }

            if let colon = token.firstIndex(of: ":") {
                let key = token[..<colon].lowercased()
                let values = token[token.index(after: colon)...]
                    .split(separator: ",")
                    .map { $0.lowercased() }
                if let field = Term.Field(rawValue: key), !values.isEmpty {
                    terms.append(Term(field: field, values: values, negated: negated))
                    continue
                }
                unknown.append(String(rawToken))
            }
            terms.append(Term(field: nil, values: [token.lowercased()], negated: negated))
        }

        self.terms = terms
        self.unknownQualifiers = unknown
    }

    /// `kind` is the subject's looked-up kind, needed for `state:`. Without it, `state:` never matches.
    func matches(_ notification: GitHubNotification, kind: FeedItem.Kind? = nil) -> Bool {
        terms.allSatisfy { term in
            let hit = term.values.contains { Self.value($0, matches: term.field, in: notification, kind: kind) }
            return hit != term.negated
        }
    }

    private static func value(_ value: String, matches field: Term.Field?, in n: GitHubNotification, kind: FeedItem.Kind?) -> Bool {
        switch field {
        case .reason:
            return n.reason.lowercased() == value
        case .type:
            return n.subject.type.lowercased() == (typeAliases[value] ?? value)
        case .repo:
            return n.repository.fullName.lowercased() == value
        case .org:
            return n.repository.owner.login.lowercased() == value
        case .state:
            switch (value, kind) {
            case ("open", .pullRequest(.open)), ("open", .pullRequest(.draft)), ("open", .issue(.open)),
                 ("draft", .pullRequest(.draft)),
                 ("merged", .pullRequest(.merged)),
                 ("closed", .pullRequest(.closed)), ("closed", .issue(.closed)), ("closed", .issue(.notPlanned)):
                return true
            default:
                return false
            }
        case .status:
            switch value {
            case "unread": return n.unread
            case "read": return !n.unread
            default: return false
            }
        case nil:
            return n.subject.title.lowercased().contains(value)
        }
    }
}
