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
    /// While set and in the future, the menu bar icon isn't highlighted and no macOS notifications are posted.
    private(set) var snoozedUntil: Date? = nil {
        didSet { defaults.set(snoozedUntil, forKey: Keys.snoozedUntil) }
    }

    private var token: String? = nil
    private var notifications: [GitHubNotification] = []
    /// State, CI and review info for notification subjects, from `GitHubClient.lookUp`.
    private var subjectDetails: [GitHubClient.SubjectRef: FeedItem] = [:]
    private var seenItemIDs: [UUID: Set<String>] {
        didSet { saveSeenItemIDs() }
    }

    @ObservationIgnored private var subjectFetchedAt: [GitHubClient.SubjectRef: Date] = [:]
    @ObservationIgnored private var notificationsLastModified: String?
    @ObservationIgnored private var notificationsMinInterval: TimeInterval = 60
    @ObservationIgnored private var notificationsFetchedAt: Date?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var snoozeTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Subject details older than this are refreshed even if the notification didn't change, to keep CI status current.
    private static let subjectMaxAge: TimeInterval = 600

    private enum Keys {
        static let tabs = "tabs"
        static let pollInterval = "pollInterval"
        static let seenItemIDs = "seenItemIDs"
        static let snoozedUntil = "snoozedUntil"
    }

    init() {
        token = KeychainStore.token.read()
        tabs = Self.loadTabs(from: defaults) ?? TabPreset.defaults
        let storedInterval = defaults.double(forKey: Keys.pollInterval)
        pollInterval = storedInterval > 0 ? storedInterval : 120
        seenItemIDs = Self.loadSeenItemIDs(from: defaults)
        selectedTabID = tabs.first(where: \.isEnabled)?.id
        if let until = defaults.object(forKey: Keys.snoozedUntil) as? Date, until > Date() {
            snoozedUntil = until
            scheduleSnoozeEnd()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: true) }
        }

        SystemNotifier.shared.activate()
        SystemNotifier.shared.onOpen = { [weak self] url, threadID in
            NSWorkspace.shared.open(url)
            if let threadID { Task { await self?.resolve(threadIDs: [threadID], done: false) } }
        }

        GlobalShortcut.register()
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
                await lookUpSubjects(client: client)
                applyNotificationFilters(announce: true)
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
                    setResult(TabResult(items: outcome.items, totalCount: outcome.totalCount, error: outcome.error),
                              for: tab, announce: true)
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
    }

    /// Fetches state, CI and review info for notification subjects that are new, changed, or stale.
    /// Failures are ignored: rows just fall back to the plain notification data.
    private func lookUpSubjects(client: GitHubClient) async {
        let now = Date()
        var needed: Set<GitHubClient.SubjectRef> = []
        for notification in notifications {
            guard let ref = notification.subjectRef else { continue }
            guard let fetchedAt = subjectFetchedAt[ref] else { needed.insert(ref); continue }
            if notification.updatedAt > fetchedAt || now.timeIntervalSince(fetchedAt) > Self.subjectMaxAge {
                needed.insert(ref)
            }
        }
        guard !needed.isEmpty, let found = try? await client.lookUp(needed) else { return }

        for ref in needed {
            subjectFetchedAt[ref] = now
            subjectDetails[ref] = found[ref]
        }
        // Drop details for subjects that no longer have a notification.
        let current = Set(notifications.compactMap(\.subjectRef))
        subjectDetails = subjectDetails.filter { current.contains($0.key) }
        subjectFetchedAt = subjectFetchedAt.filter { current.contains($0.key) }
    }

    private func notificationItems(matching query: String) -> [FeedItem] {
        let filter = NotificationFilter(query)
        return notifications.compactMap { notification in
            let details = notification.subjectRef.flatMap { subjectDetails[$0] }
            guard filter.matches(notification, kind: details?.kind) else { return nil }
            return notification.feedItem(subject: details)
        }
    }

    /// Rebuilds every notification tab from the cached threads. No network involved.
    private func applyNotificationFilters(announce: Bool = false) {
        for tab in tabs where tab.source == .notifications {
            let items = notificationItems(matching: tab.query)
            setResult(TabResult(items: items, totalCount: items.count), for: tab, announce: announce)
        }
    }

    /// Stores a tab's result. With `announce`, items that weren't in the previous result for the same
    /// query are posted as macOS notifications (if the tab has notifications on).
    private func setResult(_ result: TabResult, for tab: TabConfig, announce: Bool) {
        var result = result
        result.signature = tab.requestSignature
        let previous = results[tab.id]
        results[tab.id] = result

        // First successful load sets the baseline, so existing items don't count as "new".
        if result.error == nil, seenItemIDs[tab.id] == nil {
            seenItemIDs[tab.id] = Set(result.items.map(\.id))
        }

        guard announce, tab.notify, tab.isEnabled, !isSnoozed, result.error == nil,
              let previous, previous.error == nil, previous.signature == result.signature else { return }
        let known = Set(previous.items.map(\.id)).union(seenItemIDs[tab.id] ?? [])
        let fresh = result.items.filter { !known.contains($0.id) }
        if !fresh.isEmpty {
            SystemNotifier.shared.post(fresh, from: tab)
        }
    }

    private func resetData() {
        results = [:]
        notifications = []
        subjectDetails = [:]
        subjectFetchedAt = [:]
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
        await resolve(threadIDs: [item.notificationThreadID].compactMap { $0 }, done: false)
    }

    /// Marks as done, which also removes the notification from the github.com inbox.
    func markDone(_ item: FeedItem) async {
        await resolve(threadIDs: [item.notificationThreadID].compactMap { $0 }, done: true)
    }

    /// Applies to the notifications currently shown in the tab only; other tabs are untouched.
    func markAllRead(in tab: TabConfig) async {
        await resolve(threadIDs: (results[tab.id]?.items ?? []).compactMap(\.notificationThreadID), done: false)
    }

    func markAllDone(in tab: TabConfig) async {
        await resolve(threadIDs: (results[tab.id]?.items ?? []).compactMap(\.notificationThreadID), done: true)
    }

    /// Removes the threads locally right away, then marks them read or done on GitHub.
    /// Threads that fail are put back so they stay visible.
    private func resolve(threadIDs: [String], done: Bool) async {
        let threadIDs = Set(threadIDs)
        guard let token, !threadIDs.isEmpty else { return }

        let removed = notifications.filter { threadIDs.contains($0.id) }
        notifications.removeAll { threadIDs.contains($0.id) }
        applyNotificationFilters()

        let client = GitHubClient(token: token)
        let failed = await withTaskGroup(of: String?.self) { group in
            for id in threadIDs {
                group.addTask {
                    do {
                        if done {
                            try await client.markThreadDone(id: id)
                        } else {
                            try await client.markThreadRead(id: id)
                        }
                        return nil
                    } catch {
                        return id
                    }
                }
            }
            var failed: Set<String> = []
            for await id in group {
                if let id { failed.insert(id) }
            }
            return failed
        }

        guard !failed.isEmpty else { return }
        notifications += removed.filter { failed.contains($0.id) }
        notifications.sort { $0.updatedAt > $1.updatedAt }
        applyNotificationFilters()
        let action = done ? "done" : "read"
        globalError = failed.count == 1
            ? "Couldn't mark the notification as \(action)."
            : "Couldn't mark \(failed.count) notifications as \(action)."
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

    /// Drives the menu bar icon highlight. Always false while snoozed.
    var needsAttention: Bool {
        !isSnoozed && enabledTabs.contains { needsAttention($0) }
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

    // MARK: - Snooze

    var isSnoozed: Bool {
        snoozedUntil.map { $0 > Date() } ?? false
    }

    func snooze(until date: Date) {
        snoozedUntil = date
        scheduleSnoozeEnd()
    }

    func endSnooze() {
        snoozeTask?.cancel()
        snoozedUntil = nil
    }

    /// Tomorrow at 9:00.
    static var tomorrowMorning: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
    }

    /// Clears `snoozedUntil` when it passes so the icon updates without waiting for a refresh.
    private func scheduleSnoozeEnd() {
        snoozeTask?.cancel()
        guard let until = snoozedUntil else { return }
        snoozeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.snoozedUntil = nil
        }
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
                await lookUpSubjects(client: client)
            } catch {
                return error.localizedDescription
            }
            let count = notificationItems(matching: tab.query).count
            var message = "\(count) of \(notifications.count) unread notifications"
            let unknown = NotificationFilter(tab.query).unknownQualifiers
            if !unknown.isEmpty {
                message += " · unknown: \(unknown.joined(separator: " "))"
            }
            return message
        }
    }

    /// Turns on macOS notifications for a tab, asking for permission first. Returns false if denied.
    func enableNotifications(for tabID: UUID) async -> Bool {
        guard await SystemNotifier.shared.requestAuthorization() else { return false }
        if let index = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[index].notify = true
        }
        return true
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
        func requestSignatures(_ tabs: [TabConfig]) -> [String] {
            tabs.filter(\.isEnabled).map { "\($0.id)|\($0.requestSignature)" }
        }
        guard requestSignatures(oldValue) != requestSignatures(tabs) else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Export & import

    private struct TabsFile: Codable {
        var version = 1
        var tabs: [TabConfig]
    }

    func exportTabs() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(TabsFile(tabs: tabs))
    }

    /// Adds the tabs from an exported file (or a bare array of tabs) with fresh IDs. Returns how many were added.
    @discardableResult
    func importTabs(from data: Data) throws -> Int {
        let decoder = JSONDecoder()
        let imported: [TabConfig]
        if let file = try? decoder.decode(TabsFile.self, from: data) {
            imported = file.tabs
        } else {
            imported = try decoder.decode([TabConfig].self, from: data)
        }
        tabs += imported.map { tab in
            var tab = tab
            tab.id = UUID()
            return tab
        }
        return imported.count
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
