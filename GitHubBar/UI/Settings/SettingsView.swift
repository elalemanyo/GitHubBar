import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettings()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            TabsSettings()
                .tabItem { Label("Tabs", systemImage: "square.stack") }
        }
        .frame(width: 680, height: 460)
    }
}

// MARK: - Account

struct AccountSettings: View {
    @Environment(AppState.self) private var state

    @State private var tokenDraft = ""
    @State private var isSaving = false
    @State private var tokenError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var checkForUpdates = Updater.shared.automaticallyChecksForUpdates
    @State private var installUpdates = Updater.shared.automaticallyDownloadsUpdates

    private static let newTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,notifications&description=GitHubBar")!
    private static let tokenDocsURL = URL(string: "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic")!

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                if state.hasToken {
                    LabeledContent("Signed in as") {
                        HStack {
                            Text(state.viewer.map { "@\($0.login)" } ?? "…")
                            Button("Remove Token", role: .destructive) { state.removeToken() }
                        }
                    }
                    if let scopes = state.viewer?.scopes {
                        LabeledContent("Scopes", value: scopes.isEmpty ? "Fine-grained token (no notifications access)" : scopes.joined(separator: ", "))
                    }
                }

                HStack {
                    SecureField(state.hasToken ? "Replace token" : "Personal access token", text: $tokenDraft)
                        .onSubmit(save)
                    Button(isSaving ? "Checking…" : "Save", action: save)
                        .disabled(tokenDraft.isEmpty || isSaving)
                }
                if let tokenError {
                    Text(tokenError)
                        .foregroundStyle(Primer.dangerFg)
                }
            } header: {
                Text("GitHub")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Use a classic token with the **repo** and **notifications** scopes. Fine-grained tokens can't read notifications. The token is stored in your Keychain.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Link("Create a token on GitHub", destination: Self.newTokenURL)
                        Link("About personal access tokens", destination: Self.tokenDocsURL)
                    }
                    .foregroundStyle(Primer.accentFg)
                }
                .font(.footnote)
            }

            Section("General") {
                Picker("Refresh every", selection: $state.pollInterval) {
                    ForEach(AppState.pollIntervalOptions, id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .wide)))
                            .tag(seconds)
                    }
                }
                KeyboardShortcuts.Recorder("Open GitHubBar from anywhere", name: .togglePopover)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                if Updater.shared.isConfigured {
                    Toggle("Automatically check for updates", isOn: $checkForUpdates)
                        .onChange(of: checkForUpdates) { _, enabled in
                            Updater.shared.automaticallyChecksForUpdates = enabled
                        }
                    Toggle("Automatically download and install updates", isOn: $installUpdates)
                        .disabled(!checkForUpdates)
                        .onChange(of: installUpdates) { _, enabled in
                            Updater.shared.automaticallyDownloadsUpdates = enabled
                        }
                }
                LabeledContent("Version") {
                    HStack {
                        Text(Updater.versionDescription)
                        if Updater.shared.isConfigured {
                            Button("Check Now") { Updater.shared.checkForUpdates() }
                                .disabled(!Updater.shared.canCheckForUpdates)
                        }
                    }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        guard !tokenDraft.isEmpty, !isSaving else { return }
        isSaving = true
        tokenError = nil
        Task {
            tokenError = await state.setToken(tokenDraft)
            if tokenError == nil { tokenDraft = "" }
            isSaving = false
        }
    }
}

// MARK: - Tabs

struct TabsSettings: View {
    @Environment(AppState.self) private var state
    @State private var selection: UUID?
    /// Shown in the editor, e.g. after Copy AI Prompt; set for screenshots.
    private let editorMessage: String?
    @State private var exportDocument: TabsDocument?
    @State private var isImporting = false
    @State private var transferMessage: String?

    init(selection: UUID? = nil, editorMessage: String? = nil) {
        _selection = State(initialValue: selection)
        self.editorMessage = editorMessage
    }

    var body: some View {
        @Bindable var state = state

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(state.tabs) { tab in
                        HStack(spacing: 8) {
                            Octicon(name: tab.icon)
                                .foregroundStyle(.secondary)
                            Text(tab.title)
                                .foregroundStyle(tab.isEnabled ? .primary : .secondary)
                            Spacer()
                            if !tab.isEnabled {
                                Text("Hidden")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(tab.id)
                    }
                    .onMove { state.tabs.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))

                HStack(spacing: 0) {
                    addMenu
                    Button {
                        removeSelected()
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    Spacer()
                    Button {
                        isImporting = true
                    } label: {
                        Octicon(name: "download").frame(width: 24, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .help("Import tabs from a file")
                    Button {
                        exportDocument = (try? state.exportTabs()).map(TabsDocument.init)
                    } label: {
                        Octicon(name: "upload").frame(width: 24, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .help("Export tabs to a file")
                }
                .padding(4)

                if let transferMessage {
                    Text(transferMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .frame(width: 220)
            .padding([.leading, .vertical], 12)

            if let index = state.tabs.firstIndex(where: { $0.id == selection }) {
                TabEditor(tab: $state.tabs[index], message: editorMessage)
                    .id(state.tabs[index].id)
            } else {
                Text("Select a tab, or add one with +")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = state.tabs.first?.id }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .json,
            defaultFilename: "GitHubBar Tabs"
        ) { result in
            if case .success = result { transferMessage = "Exported \(state.tabs.count) tabs." }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let count = try state.importTabs(from: Data(contentsOf: url))
                transferMessage = "Imported \(count) tabs."
                selection = state.tabs.last?.id
            } catch {
                transferMessage = "Couldn't import: not a GitHubBar tabs file."
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Section("Notifications") {
                ForEach(TabPreset.notifications) { preset in
                    Button(preset.title) { add(preset.makeTab()) }
                }
            }
            Section("Search") {
                ForEach(TabPreset.search) { preset in
                    Button(preset.title) { add(preset.makeTab()) }
                }
            }
            Divider()
            Button("Custom Search…") {
                add(TabConfig(title: "New search", icon: "filter", source: .search, query: "is:open ", attention: .newItems))
            }
            Button("Custom Notifications…") {
                add(TabConfig(title: "New notifications", icon: "bell", source: .notifications, query: "", attention: .anyItems))
            }
        } label: {
            Image(systemName: "plus").frame(width: 24, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func add(_ tab: TabConfig) {
        state.tabs.append(tab)
        selection = tab.id
    }

    private func removeSelected() {
        guard let selection, let index = state.tabs.firstIndex(where: { $0.id == selection }) else { return }
        self.selection = nil
        state.tabs.remove(at: index)
        self.selection = state.tabs.indices.contains(index) ? state.tabs[index].id : state.tabs.last?.id
    }
}

/// Wraps exported tab JSON for `fileExporter`.
private struct TabsDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
