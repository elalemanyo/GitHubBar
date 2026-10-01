import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

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
                Rectangle().fill(Primer.borderDefault).frame(height: 1)
                if let error = state.globalError {
                    FlashBanner(message: error, variant: .danger)
                        .padding(8)
                }
                if let tab = selectedTab {
                    TabContent(tab: tab)
                        .frame(maxHeight: .infinity)
                }
            }
            Rectangle().fill(Primer.borderDefault).frame(height: 1)
            footer
        }
        .frame(width: 400, height: 520)
        .background(Primer.canvasDefault)
        .background(WindowObserver(onBecomeKey: popoverDidOpen, onResignKey: popoverDidClose))
        .onChange(of: state.selectedTabID) { oldValue, _ in
            state.markSeen(oldValue)
        }
    }

    private var selectedTab: TabConfig? {
        state.enabledTabs.first { $0.id == state.selectedTabID } ?? state.enabledTabs.first
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Group {
                if state.isRefreshing {
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

            IconButton(icon: "sync", help: "Refresh") {
                Task { await state.refresh(force: true) }
            }
            .disabled(!state.hasToken || state.isRefreshing)

            if let tab = selectedTab, state.hasToken {
                IconButton(icon: "link-external", help: "Open “\(tab.title)” on GitHub") {
                    NSWorkspace.shared.open(tab.webURL)
                }
            }

            Menu {
                Button("Settings…", action: showSettings)
                    .keyboardShortcut(",")
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
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Primer.canvasSubtle)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func popoverDidOpen() {
        if let lastRefresh = state.lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        Task { await state.refresh() }
    }

    private func popoverDidClose() {
        state.markSeen(selectedTab?.id)
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
        }
        .padding(.horizontal, 8)
        .background(Primer.canvasSubtle)
    }

    private func row(showTitles: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(state.enabledTabs) { tab in
                TabBarItem(
                    tab: tab,
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
        .help(tab.title)
    }
}

// MARK: - Tab content

private struct TabContent: View {
    @Environment(AppState.self) private var state
    let tab: TabConfig

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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(result.items) { item in
                    ItemRow(
                        item: item,
                        isNew: state.isNew(item, in: tab.id),
                        onOpen: { state.open(item) },
                        onMarkRead: item.notificationThreadID == nil ? nil : { Task { await state.markRead(item) } }
                    )
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
