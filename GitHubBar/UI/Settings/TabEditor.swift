import AppKit
import SwiftUI

struct TabEditor: View {
    @Environment(AppState.self) private var state
    @Binding var tab: TabConfig

    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showIconPicker = false
    @State private var notificationsDenied = false

    private static let searchDocs = URL(string: "https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests")!
    private static let reasonDocs = URL(string: "https://docs.github.com/en/rest/activity/notifications#about-notification-reasons")!

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $tab.title)

                LabeledContent("Icon") {
                    Button {
                        showIconPicker = true
                    } label: {
                        Octicon(name: tab.icon)
                            .frame(width: 24, height: 18)
                    }
                    .popover(isPresented: $showIconPicker, arrowEdge: .trailing) {
                        IconPicker(selection: $tab.icon)
                    }
                }

                Toggle("Show in menu bar", isOn: $tab.isEnabled)
            }

            Section {
                Picker("Source", selection: $tab.source) {
                    ForEach(TabSource.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Query", text: $tab.query, prompt: Text(placeholder), axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)

                HStack {
                    Button(isTesting ? "Testing…" : "Test Query", action: runTest)
                        .disabled(isTesting)
                    Button("Copy AI Prompt", action: copyPrompt)
                        .help("Copies a prompt with the full query syntax. Paste it into an AI assistant, describe what you want and paste the answer back here.")
                    if let testResult {
                        Text(testResult)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } footer: {
                queryHelp
                    .font(.footnote)
            }

            Section {
                Picker("Highlight menu bar icon", selection: $tab.attention) {
                    ForEach(AttentionRule.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Notify me about new items", isOn: notifyBinding)
                if notificationsDenied {
                    Text("Notifications are turned off for GitHubBar. Allow them in System Settings → Notifications.")
                        .font(.footnote)
                        .foregroundStyle(Primer.dangerFg)
                }
            } footer: {
                Text("New items are posted as macOS notifications. Nothing is sent while snoozed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: tab.source) { testResult = nil }
    }

    private var placeholder: String {
        switch tab.source {
        case .search: "is:pr is:open review-requested:@me"
        case .notifications: "reason:mention,team_mention -repo:owner/noisy"
        }
    }

    @ViewBuilder
    private var queryHelp: some View {
        switch tab.source {
        case .search:
            VStack(alignment: .leading, spacing: 4) {
                Text("Same syntax as the search bar on github.com. Use `@me` for yourself. Covers issues and pull requests.")
                    .foregroundStyle(.secondary)
                Link("Search syntax reference", destination: Self.searchDocs)
                    .foregroundStyle(Primer.accentFg)
            }
        case .notifications:
            VStack(alignment: .leading, spacing: 4) {
                Text("Filters your unread notifications. Qualifiers: `reason:` `type:` `repo:` `org:` `state:` (open, draft, merged, closed). Separate values with commas to match any, prefix with `-` to exclude, e.g. `-state:merged,closed`. Plain words match the title. Leave empty for all.")
                    .foregroundStyle(.secondary)
                Link("Notification reasons", destination: Self.reasonDocs)
                    .foregroundStyle(Primer.accentFg)
            }
        }
    }

    /// Turning notifications on asks for macOS permission first.
    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { tab.notify },
            set: { enabled in
                guard enabled else {
                    tab.notify = false
                    return
                }
                let tabID = tab.id
                Task { notificationsDenied = !(await state.enableNotifications(for: tabID)) }
            }
        )
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tab.aiPrompt, forType: .string)
        testResult = "Prompt copied. Paste it into your AI assistant."
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        let snapshot = tab
        Task {
            testResult = await state.test(snapshot)
            isTesting = false
        }
    }
}

private struct IconPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8)

    var body: some View {
        VStack(spacing: 8) {
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(names, id: \.self) { name in
                        Button {
                            selection = name
                            dismiss()
                        } label: {
                            Octicon(name: name)
                                .frame(width: 30, height: 30)
                                .foregroundStyle(name == selection ? Primer.fgOnEmphasis : Primer.fgDefault)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(name == selection ? Primer.accentEmphasis : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 200)
        }
        .padding(10)
        .frame(width: 290)
    }

    private var names: [String] {
        filter.isEmpty ? OcticonCatalog.names : OcticonCatalog.names.filter { $0.localizedCaseInsensitiveContains(filter) }
    }
}
