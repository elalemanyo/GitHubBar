import AppKit
import KeyboardShortcuts
import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    @State private var selectedItemID: String?
    @State private var showShortcuts = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !state.hasToken {
                BlankSlate(icon: "mark-github", title: "Connect to GitHub",
                           message: "Add a personal access token to see your notifications and pull requests.") {
                    Button("Open Settings…", action: showSettings)
                }
            } else if state.enabledTabs.isEmpty {
                BlankSlate(icon: "filter", title: "No tabs", message: "Add a tab in Settings.") {
                    Button("Open Settings…", action: showSettings)
                }
            } else {
                TabBar()
                if let error = state.globalError {
                    FlashBanner(message: error, variant: .danger)
                        .padding(8)
                }
                if let tab = selectedTab {
                    TabContent(tab: tab, selectedItemID: $selectedItemID)
                        .frame(maxHeight: .infinity)
                }
            }
            Rectangle().fill(Primer.borderDefault).frame(height: 1)
            footer
        }
        .frame(width: 400, height: 520)
        .background(Primer.canvasDefault)
        .overlay {
            if showShortcuts {
                ShortcutsOverlay { showShortcuts = false }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .down, action: handleKey)
        .background(WindowObserver(onBecomeKey: popoverDidOpen, onResignKey: popoverDidClose))
        .onChange(of: state.selectedTabID) { oldValue, _ in
            state.markSeen(oldValue)
            selectedItemID = nil
        }
    }

    private var selectedTab: TabConfig? {
        state.enabledTabs.first { $0.id == state.selectedTabID } ?? state.enabledTabs.first
    }

    private var currentItems: [FeedItem] {
        selectedTab.flatMap { state.results[$0.id]?.items } ?? []
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Group {
                if let until = state.snoozedUntil, state.isSnoozed {
                    Button {
                        state.endSnooze()
                    } label: {
                        HStack(spacing: 4) {
                            Octicon(name: "bell-slash", size: 12)
                            Text("Snoozed until \(until.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to resume")
                } else if state.isRefreshing {
                    Text("Updating…")
                } else if let lastRefresh = state.lastRefresh {
                    Text("Updated \(lastRefresh, format: .relative(presentation: .named))")
                } else if let login = state.viewer?.login {
                    Text("@\(login)")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Primer.fgMuted)
            .padding(.leading, 6)

            Spacer()

            if let tab = selectedTab, tab.source == .notifications, !currentItems.isEmpty {
                let count = currentItems.count
                IconButton(icon: "read", help: "Mark all \(count) as read") {
                    Task { await state.markAllRead(in: tab) }
                }
                IconButton(icon: "check", help: "Mark all \(count) as done") {
                    Task { await state.markAllDone(in: tab) }
                }
                Rectangle().fill(Primer.borderDefault).frame(width: 1, height: 16).padding(.horizontal, 4)
            }

            IconButton(icon: "sync", help: "Refresh · ⌘R") {
                Task { await state.refresh(force: true) }
            }
            .disabled(!state.hasToken || state.isRefreshing)

            if let tab = selectedTab, state.hasToken {
                IconButton(icon: "link-external", help: "Open “\(tab.title)” on GitHub") {
                    NSWorkspace.shared.open(tab.webURL)
                }
            }

            menu
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Primer.canvasSubtle)
    }

    private var menu: some View {
        Menu {
            Button("Settings…", action: showSettings)
                .keyboardShortcut(",")
            Button("Keyboard Shortcuts") { showShortcuts = true }
            Divider()
            if state.isSnoozed {
                Button("Resume Highlighting", action: state.endSnooze)
            } else {
                Menu("Snooze Highlighting") {
                    Button("For 1 Hour") { state.snooze(until: Date().addingTimeInterval(3600)) }
                    Button("For 4 Hours") { state.snooze(until: Date().addingTimeInterval(4 * 3600)) }
                    Button("Until Tomorrow") { state.snooze(until: AppState.tomorrowMorning) }
                }
            }
            Divider()
            Button("Quit GitHubBar") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Octicon(name: "gear")
                .foregroundStyle(Primer.fgMuted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if showShortcuts {
            if press.key == .escape || press.characters == "?" {
                showShortcuts = false
                return .handled
            }
            return .ignored
        }

        if press.modifiers.contains(.command) {
            switch press.characters {
            case "r":
                Task { await state.refresh(force: true) }
            case ",":
                showSettings()
            case let digit where Int(digit).map((1...9).contains) == true:
                selectTab(at: Int(digit)! - 1)
            default:
                return .ignored
            }
            return .handled
        }

        switch press.key {
        case .downArrow: moveSelection(by: 1); return .handled
        case .upArrow: moveSelection(by: -1); return .handled
        case .leftArrow: switchTab(by: -1); return .handled
        case .rightArrow: switchTab(by: 1); return .handled
        case .return: openSelected(); return .handled
        case .escape: GlobalShortcut.closePopover(); return .handled
        default: break
        }

        switch press.characters {
        case "j": moveSelection(by: 1)
        case "k": moveSelection(by: -1)
        case "o": openSelected()
        case "e": resolveSelected(done: true)
        case "I": resolveSelected(done: false)
        case "?": showShortcuts = true
        default: return .ignored
        }
        return .handled
    }

    private func selectTab(at index: Int) {
        guard state.enabledTabs.indices.contains(index) else { return }
        state.selectedTabID = state.enabledTabs[index].id
    }

    private func switchTab(by offset: Int) {
        let tabs = state.enabledTabs
        guard let current = tabs.firstIndex(where: { $0.id == selectedTab?.id }) else { return }
        selectTab(at: (current + offset + tabs.count) % tabs.count)
    }

    private func moveSelection(by offset: Int) {
        let items = currentItems
        guard !items.isEmpty else { return }
        guard let current = items.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = offset > 0 ? items.first?.id : items.last?.id
            return
        }
        selectedItemID = items[min(max(current + offset, 0), items.count - 1)].id
    }

    private func openSelected() {
        guard let item = currentItems.first(where: { $0.id == selectedItemID }) else { return }
        state.open(item)
    }

    /// Marks the selected notification read or done and moves the selection to the next row.
    private func resolveSelected(done: Bool) {
        let items = currentItems
        guard let index = items.firstIndex(where: { $0.id == selectedItemID }),
              items[index].notificationThreadID != nil else { return }
        let item = items[index]
        let remaining = items.filter { $0.id != item.id }
        selectedItemID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        Task {
            if done {
                await state.markDone(item)
            } else {
                await state.markRead(item)
            }
        }
    }

    // MARK: Window

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func popoverDidOpen() {
        isFocused = true
        if let lastRefresh = state.lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        Task { await state.refresh() }
    }

    private func popoverDidClose() {
        state.markSeen(selectedTab?.id)
        showShortcuts = false
    }
}

// MARK: - Tab bar (Primer UnderlineNav)

private struct TabBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showTitles: true)
            ScrollView(.horizontal, showsIndicators: false) {
                row(showTitles: false)
            }
            // Hug the row's height so the active underline sits on the bottom border.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Drawn behind the tabs so the active underline overlaps it, like Primer's UnderlineNav.
        .background(alignment: .bottom) {
            Rectangle().fill(Primer.borderDefault).frame(height: 1)
        }
        .background(Primer.canvasSubtle)
    }

    private func row(showTitles: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(state.enabledTabs.enumerated()), id: \.element.id) { index, tab in
                TabBarItem(
                    tab: tab,
                    shortcut: index < 9 ? "⌘\(index + 1)" : nil,
                    showTitle: showTitles,
                    isSelected: tab.id == (state.selectedTabID ?? state.enabledTabs.first?.id),
                    count: state.badgeCount(for: tab),
                    needsAttention: state.needsAttention(tab)
                ) {
                    state.selectedTabID = tab.id
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TabBarItem: View {
    let tab: TabConfig
    let shortcut: String?
    let showTitle: Bool
    let isSelected: Bool
    let count: Int
    let needsAttention: Bool
    let action: () -> Void

    @State private var isHovering = false

    /// UnderlineNav's active indicator color (`underlineNav.borderColor.active`).
    private static let activeUnderline = Color(light: 0xFD8C73, dark: 0xF78166)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Octicon(name: tab.icon)
                    .foregroundStyle(isSelected ? Primer.fgDefault : Primer.fgMuted)
                if showTitle {
                    Text(tab.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Primer.fgDefault)
                        .lineLimit(1)
                }
                if count > 0 {
                    CounterLabel(count: count, emphasized: needsAttention)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Primer.rowHover : .clear))
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? Self.activeUnderline : .clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(shortcut.map { "\(tab.title) · \($0)" } ?? tab.title)
    }
}

// MARK: - Tab content

private struct TabContent: View {
    @Environment(AppState.self) private var state
    let tab: TabConfig
    @Binding var selectedItemID: String?

    var body: some View {
        if let result = state.results[tab.id] {
            VStack(spacing: 0) {
                if tab.source == .notifications, !state.canReadNotifications {
                    FlashBanner(message: "This token can't read notifications. Use a classic token with the “notifications” scope.")
                        .padding(8)
                } else if let error = result.error {
                    FlashBanner(message: error, variant: .danger)
                        .padding(8)
                }

                if result.items.isEmpty {
                    if result.error == nil {
                        BlankSlate(icon: tab.source == .notifications ? "inbox" : "check-circle",
                                   title: "All caught up",
                                   message: "Nothing matches “\(tab.title)” right now.")
                    } else {
                        Spacer()
                    }
                } else {
                    list(result)
                }
            }
        } else if tab.source == .search, tab.query.isEmpty {
            BlankSlate(icon: "filter", title: "Empty query", message: "Set a search query for this tab in Settings.")
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func list(_ result: TabResult) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(result.items) { item in
                        ItemRow(
                            item: item,
                            isNew: state.isNew(item, in: tab.id),
                            isSelected: item.id == selectedItemID,
                            onOpen: { state.open(item) },
                            onMarkRead: notificationAction(for: item) { await state.markRead($0) },
                            onMarkDone: notificationAction(for: item) { await state.markDone($0) }
                        )
                        .id(item.id)
                        Rectangle().fill(Primer.borderMuted).frame(height: 1)
                    }

                    if result.totalCount > result.items.count {
                        Button {
                            NSWorkspace.shared.open(tab.webURL)
                        } label: {
                            Text("Showing \(result.items.count) of \(result.totalCount) · View all on GitHub")
                                .font(.system(size: 12))
                                .foregroundStyle(Primer.accentFg)
                                .padding(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onChange(of: selectedItemID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
            }
        }
    }
}

extension TabContent {
    /// Row action for notification items; `nil` for search results, which can't be marked.
    private func notificationAction(for item: FeedItem, _ action: @escaping (FeedItem) async -> Void) -> (() -> Void)? {
        guard item.notificationThreadID != nil else { return nil }
        return { Task { await action(item) } }
    }
}

// MARK: - Keyboard shortcuts help

private struct ShortcutsOverlay: View {
    let onClose: () -> Void

    private let sections: [(title: String, rows: [(keys: String, label: String)])] = [
        ("Navigation", [
            ("⌘1 – ⌘9", "Switch to tab"),
            ("← →", "Previous / next tab"),
            ("J  ↓", "Next item"),
            ("K  ↑", "Previous item"),
            ("O  ↩", "Open in browser"),
        ]),
        ("Notifications", [
            ("E", "Mark as done"),
            ("⇧I", "Mark as read"),
        ]),
        ("General", [
            ("⌘R", "Refresh"),
            ("⌘,", "Settings"),
            ("?", "Show / hide shortcuts"),
            ("Esc", "Close"),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Keyboard shortcuts")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    IconButton(icon: "x", help: "Close · Esc", action: onClose)
                }

                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Primer.fgMuted)
                        ForEach(section.rows, id: \.label) { row in
                            HStack {
                                Text(row.label)
                                    .font(.system(size: 12))
                                Spacer()
                                KeyHint(row.keys)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Anywhere")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Primer.fgMuted)
                    HStack {
                        Text("Open GitHubBar")
                            .font(.system(size: 12))
                        Spacer()
                        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePopover) {
                            KeyHint(shortcut.description)
                        } else {
                            Text("Set in Settings")
                                .font(.system(size: 11))
                                .foregroundStyle(Primer.fgMuted)
                        }
                    }
                }
            }
            .foregroundStyle(Primer.fgDefault)
            .padding(16)
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 12).fill(Primer.canvasDefault))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Primer.borderDefault))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        }
    }
}

/// Primer-style `<kbd>`.
private struct KeyHint: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Primer.fgDefault)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(Primer.canvasSubtle))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Primer.borderDefault))
    }
}

// MARK: - Window observation

/// Reports when the hosting window (the menu bar popover) gains or loses key status.
/// `onAppear`/`onDisappear` aren't reliable inside `MenuBarExtra` windows.
private struct WindowObserver: NSViewRepresentable {
    let onBecomeKey: () -> Void
    let onResignKey: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onBecomeKey = onBecomeKey
        view.onResignKey = onResignKey
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onBecomeKey = onBecomeKey
        view.onResignKey = onResignKey
    }

    final class ObserverView: NSView {
        var onBecomeKey: (() -> Void)?
        var onResignKey: (() -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.onBecomeKey?()
            })
            observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.onResignKey?()
            })
        }
    }
}
