import Foundation

extension TabConfig {
    /// A prompt for an AI assistant that explains this tab's query syntax, so anyone can describe
    /// what they want in plain words and paste back a working query.
    var aiPrompt: String {
        let current = query.trimmingCharacters(in: .whitespaces)
        let currentLine = current.isEmpty ? "(none yet)" : current

        switch source {
        case .search:
            return """
            Write a query for a tab in GitHubBar, a macOS menu bar app for GitHub.

            The tab shows GitHub issues and pull requests using the same syntax as the github.com search bar, \
            for example: is:pr is:open review-requested:@me archived:false
            - Use @me for the current user (author:@me, assignee:@me, mentions:@me, review-requested:@me).
            - Only issues and pull requests are searched, so use qualifiers like is:pr, is:issue, is:open, \
            repo:, org:, user:, label:, review:, status:, draft:, archived:, updated:, created:, sort:.
            - Reference: https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests

            Current query: \(currentLine)

            What I want to see: <describe it here>

            Reply with only the query on a single line, no explanation.
            """

        case .notifications:
            return """
            Write a filter for a notifications tab in GitHubBar, a macOS menu bar app for GitHub.

            The tab filters my unread GitHub notifications with this syntax (it's GitHubBar's own syntax, \
            not GitHub search):
            - reason: why I got it: review_requested, mention, team_mention, assign, author, comment, \
            ci_activity, state_change, security_alert, subscribed, manual, invitation, approval_requested
            - type: what it's about: PullRequest (or pr), Issue, Release, Discussion, CheckSuite (or ci), Commit
            - state: state of the pull request or issue: open (includes drafts), draft, merged, closed
            - repo: a repository, as owner/name
            - org: the repository owner (an organization or a user)
            - Plain words match the notification title.

            Rules: terms are combined with AND. Comma-separated values mean "any of", e.g. \
            reason:mention,team_mention. A leading - excludes, e.g. -org:acme,globex or -state:merged,closed. \
            There is no OR between different qualifiers and no parentheses. An empty filter shows all unread notifications.

            Current filter: \(currentLine)

            What I want to see: <describe it here>

            Reply with only the filter on a single line, no explanation.
            """
        }
    }
}
