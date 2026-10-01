import ServiceManagement
import SwiftUI

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

private struct AccountSettings: View {
    @Environment(AppState.self) private var state

    @State private var tokenDraft = ""
    @State private var isSaving = false
    @State private var tokenError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private static let newTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,notifications&description=GitHubBar")!

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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use a classic token with the **repo** and **notifications** scopes. Fine-grained tokens can't read notifications. The token is stored in your Keychain.")
                    Link("Create a token on GitHub…", destination: Self.newTokenURL)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("General") {
                Picker("Refresh every", selection: $state.pollInterval) {
                    ForEach(AppState.pollIntervalOptions, id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .wide)))
                            .tag(seconds)
                    }
                }
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

private struct TabsSettings: View {
    @Environment(AppState.self) private var state
    @State private var selection: UUID?

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
                }
                .padding(4)
            }
            .frame(width: 220)
            .padding([.leading, .vertical], 12)

            if let index = state.tabs.firstIndex(where: { $0.id == selection }) {
                TabEditor(tab: $state.tabs[index])
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
