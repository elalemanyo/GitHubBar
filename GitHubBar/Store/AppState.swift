import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let pollIntervalOptions: [TimeInterval] = [60, 120, 300, 600]

    // MARK: Settings

    var tabs: [TabConfig] {
        didSet { tabsDidChange(from: oldValue) }
    }

    var pollInterval: TimeInterval {
        didSet {
            defaults.set(pollInterval, forKey: Keys.pollInterval)
            startPolling()
        }
    }

    private(set) var viewer: GitHubClient.Viewer? = nil
    var hasToken: Bool { token != nil }

    // MARK: Runtime

    private(set) var results: [UUID: TabResult] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date? = nil
    /// Errors that affect every tab (bad token, rate limit, offline).
    private(set) var globalError: String? = nil
    var selectedTabID: UUID? = nil

    private var token: String? = nil
    private var notifications: [GitHubNotification] = []
    private var seenItemIDs: [UUID: Set<String>] {
        didSet { saveSeenItemIDs() }
    }

    @ObservationIgnored private var notificationsLastModified: String?
    @ObservationIgnored private var notificationsMinInterval: TimeInterval = 60
    @ObservationIgnored private var notificationsFetchedAt: Date?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let tabs = "tabs"
        static let pollInterval = "pollInterval"
        static let seenItemIDs = "seenItemIDs"
    }

    init() {
        token = KeychainStore.token.read()
        tabs = Self.loadTabs(from: defaults) ?? TabPreset.defaults
        let storedInterval = defaults.double(forKey: Keys.pollInterval)
        pollInterval = storedInterval > 0 ? storedInterval : 120
        seenItemIDs = Self.loadSeenItemIDs(from: defaults)
        selectedTabID = tabs.first(where: \.isEnabled)?.id

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: true) }
        }

        startPolling()
    }

    var enabledTabs: [TabConfig] { tabs.filter(\.isEnabled) }

    // MARK: - Token

    /// Validates the token against `/user` and stores it in the Keychain. Returns an error message on failure.
    func setToken(_ newToken: String) async -> String? {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a token." }
        do {
            let viewer = try await GitHubClient(token: trimmed).viewer()
            guard KeychainStore.token.save(trimmed) else { return "Couldn't save the token to the Keychain." }
            token = trimmed
            self.viewer = viewer
            resetData()
            startPolling()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeToken() {
        KeychainStore.token.delete()
        token = nil
        viewer = nil
        pollTask?.cancel()
        resetData()
    }

    /// Whether the current token can read notifications. Fine-grained tokens report no scopes and can't.
    var canReadNotifications: Bool {
        guard let viewer else { return true }
        return viewer.scopes.contains("notifications") || viewer.scopes.contains("repo")
    }

    // MARK: - Refresh

    func startPolling() {
        pollTask?.cancel()
        guard token != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.pollInterval ?? 120
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refresh(force: Bool = false) async {
        guard let token, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let client = GitHubClient(token: token)
        let enabled = enabledTabs
        var failure: Error?

        if viewer == nil {
            viewer = try? await client.viewer()
        }

        if enabled.contains(where: { $0.source == .notifications }) {
            do {
                try await fetchNotifications(client: client, force: force)
            } catch {
                failure = error
                for tab in enabled where tab.source == .notifications {
                    results[tab.id, default: TabResult()].error = error.localizedDescription
                }
            }
        }

        let searchTabs = enabled.filter { $0.source == .search && !$0.query.isEmpty }
        if !searchTabs.isEmpty {
            do {
                let outcomes = try await client.search(searchTabs.map { ($0.id.uuidString, $0.query) })
                for tab in searchTabs {
                    guard let outcome = outcomes[tab.id.uuidString] else { continue }
                    setResult(TabResult(items: outcome.items, totalCount: outcome.totalCount, error: outcome.error), for: tab.id)
                }
            } catch {
                failure = error
                for tab in searchTabs {
                    results[tab.id, default: TabResult()].error = error.localizedDescription
                }
            }
        }

        globalError = failure.flatMap(Self.globalMessage(for:))
        if failure == nil { lastRefresh = Date() }
    }

    private func fetchNotifications(client: GitHubClient, force: Bool) async throws {
        if !force, let fetchedAt = notificationsFetchedAt,
           Date().timeIntervalSince(fetchedAt) < notificationsMinInterval {
            return
        }

        let fetch = try await client.notifications(ifModifiedSince: force ? nil : notificationsLastModified)
        notificationsFetchedAt = Date()
        switch fetch {
        case .notModified(let interval):
            if let interval { notificationsMinInterval = TimeInterval(interval) }
        case .updated(let threads, let lastModified, let interval):
            if let interval { notificationsMinInterval = TimeInterval(interval) }
            notificationsLastModified = lastModified
            notifications = threads.sorted { $0.updatedAt > $1.updatedAt }
        }
        applyNotificationFilters()
    }

    /// Rebuilds every notification tab from the cached threads. No network involved.
    private func applyNotificationFilters() {
        for tab in tabs where tab.source == .notifications {
            let filter = NotificationFilter(tab.query)
            let items = notifications.filter(filter.matches).map(\.feedItem)
            setResult(TabResult(items: items, totalCount: items.count), for: tab.id)
        }
    }

    private func setResult(_ result: TabResult, for tabID: UUID) {
        results[tabID] = result
        // First successful load sets the baseline, so existing items don't count as "new".
        if result.error == nil, seenItemIDs[tabID] == nil {
            seenItemIDs[tabID] = Set(result.items.map(\.id))
        }
    }

    private func resetData() {
        results = [:]
        notifications = []
        notificationsLastModified = nil
        notificationsFetchedAt = nil
        globalError = nil
        lastRefresh = nil
    }

    private static func globalMessage(for error: Error) -> String? {
        switch error {
        case GitHubError.unauthorized, GitHubError.rateLimited:
            return error.localizedDescription
        case let error as URLError where error.code == .notConnectedToInternet:
            return "You're offline."
        default:
            return nil
        }
    }

    // MARK: - Items

    func markRead(_ item: FeedItem) async {
        guard let token, let threadID = item.notificationThreadID else { return }
        do {
            try await GitHubClient(token: token).markThreadRead(id: threadID)
            notifications.removeAll { $0.id == threadID }
            applyNotificationFilters()
        } catch {
            globalError = error.localizedDescription
        }
    }

    func open(_ item: FeedItem) {
        NSWorkspace.shared.open(item.url)
        if item.notificationThreadID != nil {
            Task { await markRead(item) }
        }
    }

    // MARK: - Attention

    func newItemCount(for tab: TabConfig) -> Int {
        guard let items = results[tab.id]?.items else { return 0 }
        let seen = seenItemIDs[tab.id] ?? []
        return items.filter { !seen.contains($0.id) }.count
    }

    /// Whether the item appeared after the tab was last viewed.
    func isNew(_ item: FeedItem, in tabID: UUID) -> Bool {
        guard let seen = seenItemIDs[tabID] else { return false }
        return !seen.contains(item.id)
    }

    func needsAttention(_ tab: TabConfig) -> Bool {
        switch tab.attention {
        case .never: false
        case .anyItems: (results[tab.id]?.totalCount ?? 0) > 0
        case .newItems: newItemCount(for: tab) > 0
        }
    }

    var needsAttention: Bool {
        enabledTabs.contains { needsAttention($0) }
    }

    /// Number shown on the tab: new items for `.newItems` tabs, total otherwise.
    func badgeCount(for tab: TabConfig) -> Int {
        tab.attention == .newItems ? newItemCount(for: tab) : (results[tab.id]?.totalCount ?? 0)
    }

    func markSeen(_ tabID: UUID?) {
        guard let tabID, let items = results[tabID]?.items else { return }
        let ids = Set(items.map(\.id))
        if seenItemIDs[tabID] != ids { seenItemIDs[tabID] = ids }
    }

    // MARK: - Tab editing

    /// Runs a tab's query once and describes the outcome, for the "Test" button in settings.
    func test(_ tab: TabConfig) async -> String {
        guard let token else { return "Add a token first." }
        let client = GitHubClient(token: token)
        switch tab.source {
        case .search:
            guard !tab.query.isEmpty else { return "Enter a query." }
            do {
                let outcome = try await client.search([("test", tab.query)], first: 1)["test"]
                if let error = outcome?.error { return error }
                return "\(outcome?.totalCount ?? 0) results"
            } catch {
                return error.localizedDescription
            }
        case .notifications:
            do {
                try await fetchNotifications(client: client, force: notificationsFetchedAt == nil)
            } catch {
                return error.localizedDescription
            }
            let filter = NotificationFilter(tab.query)
            let count = notifications.filter(filter.matches).count
            var message = "\(count) of \(notifications.count) unread notifications"
            if !filter.unknownQualifiers.isEmpty {
                message += " · unknown: \(filter.unknownQualifiers.joined(separator: " "))"
            }
            return message
        }
    }

    private func tabsDidChange(from oldValue: [TabConfig]) {
        saveTabs()

        let ids = Set(tabs.map(\.id))
        results = results.filter { ids.contains($0.key) }
        seenItemIDs = seenItemIDs.filter { ids.contains($0.key) }
        if let selectedTabID, !enabledTabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = enabledTabs.first?.id
        }

        applyNotificationFilters()

        // Only hit the network when something that affects a request changed; renames or icon changes don't.
        func requestSignature(_ tabs: [TabConfig]) -> [String] {
            tabs.filter(\.isEnabled).map { "\($0.id)|\($0.source.rawValue)|\($0.query)" }
        }
        guard requestSignature(oldValue) != requestSignature(tabs) else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Persistence

    private func saveTabs() {
        if let data = try? JSONEncoder().encode(tabs) {
            defaults.set(data, forKey: Keys.tabs)
        }
    }

    private static func loadTabs(from defaults: UserDefaults) -> [TabConfig]? {
        guard let data = defaults.data(forKey: Keys.tabs) else { return nil }
        return try? JSONDecoder().decode([TabConfig].self, from: data)
    }

    private func saveSeenItemIDs() {
        let encodable = Dictionary(uniqueKeysWithValues: seenItemIDs.map { ($0.key.uuidString, Array($0.value)) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Keys.seenItemIDs)
        }
    }

    private static func loadSeenItemIDs(from defaults: UserDefaults) -> [UUID: Set<String>] {
        guard let data = defaults.data(forKey: Keys.seenItemIDs),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            UUID(uuidString: key).map { ($0, Set(value)) }
        })
    }
}
