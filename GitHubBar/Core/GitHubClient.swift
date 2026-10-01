import Foundation

enum GitHubError: LocalizedError {
    case unauthorized
    case rateLimited(reset: Date?)
    case http(status: Int, message: String?)
    case graphQL(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "The token is invalid or expired."
        case .rateLimited(let reset):
            if let reset {
                "Rate limit reached. Resets \(reset.formatted(date: .omitted, time: .shortened))."
            } else {
                "Rate limit reached."
            }
        case .http(let status, let message):
            message.map { "GitHub returned \(status): \($0)" } ?? "GitHub returned \(status)."
        case .graphQL(let message):
            message
        case .invalidResponse:
            "Unexpected response from GitHub."
        }
    }
}

enum NotificationsFetch {
    case notModified(pollInterval: Int?)
    case updated([GitHubNotification], lastModified: String?, pollInterval: Int?)
}

struct SearchOutcome {
    var items: [FeedItem] = []
    var totalCount = 0
    var error: String?
}

struct GitHubClient: Sendable {
    let token: String

    private static let apiBase = URL(string: "https://api.github.com")!

    /// No URL cache: we handle `If-Modified-Since` ourselves and need to see the 304s.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - User

    struct Viewer {
        let login: String
        /// Scopes of a classic token. Empty for fine-grained tokens.
        let scopes: [String]
    }

    func viewer() async throws -> Viewer {
        struct User: Decodable { let login: String }
        let (data, response) = try await send(request(path: "/user"))
        let user = try Self.decoder.decode(User.self, from: data)
        let scopes = (response.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Viewer(login: user.login, scopes: scopes)
    }

    // MARK: - Notifications

    /// Fetches unread notifications. Pass the previous `Last-Modified` value to make the request
    /// conditional; a 304 doesn't count against the rate limit.
    func notifications(ifModifiedSince: String?, maxPages: Int = 3) async throws -> NotificationsFetch {
        var first = request(path: "/notifications", query: [URLQueryItem(name: "per_page", value: "50")])
        if let ifModifiedSince {
            first.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await send(first, allowNotModified: true)
        let pollInterval = response.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(Int.init)
        if response.statusCode == 304 {
            return .notModified(pollInterval: pollInterval)
        }

        var all = try Self.decoder.decode([GitHubNotification].self, from: data)
        var next = Self.nextPageURL(from: response)
        var page = 1
        while let url = next, page < maxPages {
            let (data, response) = try await send(request(url: url))
            all += try Self.decoder.decode([GitHubNotification].self, from: data)
            next = Self.nextPageURL(from: response)
            page += 1
        }

        return .updated(all,
                        lastModified: response.value(forHTTPHeaderField: "Last-Modified"),
                        pollInterval: pollInterval)
    }

    func markThreadRead(id: String) async throws {
        var request = request(path: "/notifications/threads/\(id)")
        request.httpMethod = "PATCH"
        _ = try await send(request)
    }

    // MARK: - Search

    /// Runs several GitHub searches in a single GraphQL request, one alias per query.
    /// A bad query only fails its own entry; the others still return results.
    func search(_ queries: [(key: String, query: String)], first: Int = 30) async throws -> [String: SearchOutcome] {
        guard !queries.isEmpty else { return [:] }

        let variables = queries.indices.map { "$q\($0): String!" }.joined(separator: ", ")
        let fields = queries.indices.map { index in
            """
              t\(index): search(query: $q\(index), type: ISSUE, first: \(first)) {
                issueCount
                nodes { __typename ...PR ...Issue }
              }
            """
        }.joined(separator: "\n")

        let document = """
        query(\(variables)) {
        \(fields)
        }
        \(Self.searchFragments)
        """

        var variableValues: [String: String] = [:]
        for (index, entry) in queries.enumerated() {
            variableValues["q\(index)"] = entry.query
        }

        var request = request(path: "/graphql")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": document,
            "variables": variableValues,
        ])

        let (data, _) = try await send(request)
        let response = try Self.decoder.decode(GraphQLSearchResponse.self, from: data)

        var errorsByAlias: [String: String] = [:]
        var globalErrors: [String] = []
        for error in response.errors ?? [] {
            if case .key(let alias)? = error.path?.first {
                errorsByAlias[alias] = error.message
            } else {
                globalErrors.append(error.message)
            }
        }
        guard let payload = response.data else {
            throw GitHubError.graphQL(globalErrors.first ?? "Search failed.")
        }

        var outcomes: [String: SearchOutcome] = [:]
        for (index, entry) in queries.enumerated() {
            let alias = "t\(index)"
            if let connection = payload[alias] ?? nil {
                outcomes[entry.key] = SearchOutcome(
                    items: connection.nodes.compactMap { $0?.feedItem },
                    totalCount: connection.issueCount,
                    error: errorsByAlias[alias]
                )
            } else {
                outcomes[entry.key] = SearchOutcome(error: errorsByAlias[alias] ?? globalErrors.first ?? "Search failed.")
            }
        }
        return outcomes
    }

    // `state` is aliased because PullRequestState and IssueState can't share a response name.
    private static let searchFragments = """
    fragment PR on PullRequest {
      id title url updatedAt number isDraft reviewDecision
      prState: state
      author { login }
      repository { nameWithOwner }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    fragment Issue on Issue {
      id title url updatedAt number stateReason
      issueState: state
      author { login }
      repository { nameWithOwner }
    }
    """

    // MARK: - Transport

    private func request(path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return request(url: components.url!)
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 30
        return request
    }

    private func send(_ request: URLRequest, allowNotModified: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 304 where allowNotModified:
            return (data, http)
        case 401:
            throw GitHubError.unauthorized
        case 403 where http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0", 429:
            let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            throw GitHubError.rateLimited(reset: reset)
        default:
            struct Message: Decodable { let message: String }
            let message = try? Self.decoder.decode(Message.self, from: data).message
            throw GitHubError.http(status: http.statusCode, message: message)
        }
    }

    /// Parses `Link: <https://...>; rel="next", ...`.
    private static func nextPageURL(from response: HTTPURLResponse) -> URL? {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in link.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains("rel=\"next\"") else { continue }
            let raw = pieces[0].trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            return URL(string: raw)
        }
        return nil
    }
}

// MARK: - GraphQL decoding

private struct GraphQLSearchResponse: Decodable {
    let data: [String: SearchConnection?]?
    let errors: [GraphQLError]?

    struct SearchConnection: Decodable {
        let issueCount: Int
        let nodes: [SearchNode?]
    }

    struct GraphQLError: Decodable {
        let message: String
        let path: [PathComponent]?
    }

    enum PathComponent: Decodable {
        case key(String)
        case index(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let key = try? container.decode(String.self) {
                self = .key(key)
            } else {
                self = .index(try container.decode(Int.self))
            }
        }
    }
}

private struct SearchNode: Decodable {
    struct Login: Decodable { let login: String }
    struct Repository: Decodable { let nameWithOwner: String }
    struct Commits: Decodable {
        struct Node: Decodable { let commit: Commit }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String }
        let nodes: [Node?]
    }

    let typename: String?
    let id: String?
    let title: String?
    let url: URL?
    let updatedAt: Date?
    let number: Int?
    let isDraft: Bool?
    let reviewDecision: String?
    let prState: String?
    let issueState: String?
    let stateReason: String?
    let author: Login?
    let repository: Repository?
    let commits: Commits?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id, title, url, updatedAt, number, isDraft, reviewDecision
        case prState, issueState, stateReason, author, repository, commits
    }

    var feedItem: FeedItem? {
        guard let id, let title, let url, let updatedAt, let repository else { return nil }

        let kind: FeedItem.Kind
        switch (typename, prState ?? issueState) {
        case ("PullRequest", "MERGED"): kind = .pullRequest(.merged)
        case ("PullRequest", "CLOSED"): kind = .pullRequest(.closed)
        case ("PullRequest", _): kind = .pullRequest(isDraft == true ? .draft : .open)
        case ("Issue", "CLOSED"): kind = .issue(stateReason == "NOT_PLANNED" ? .notPlanned : .closed)
        case ("Issue", _): kind = .issue(.open)
        default: kind = .other
        }

        let rollup = commits?.nodes.compactMap { $0 }.last?.commit.statusCheckRollup?.state
        let checkStatus: FeedItem.CheckStatus? = switch rollup {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: nil
        }

        let review: FeedItem.ReviewDecision? = switch reviewDecision {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        default: nil
        }

        return FeedItem(
            id: id,
            kind: kind,
            title: title,
            repository: repository.nameWithOwner,
            number: number,
            url: url,
            updatedAt: updatedAt,
            author: author?.login,
            detail: nil,
            checkStatus: checkStatus,
            reviewDecision: review
        )
    }
}
