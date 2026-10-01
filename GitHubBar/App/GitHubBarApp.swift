import SwiftUI

@main
struct GitHubBarApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(state)
        } label: {
            MenuBarIcon(needsAttention: state.needsAttention)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
