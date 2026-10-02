import SwiftUI

@main
struct GitHubBarApp: App {
    @State private var state: AppState

    init() {
        #if DEBUG
        // `GitHubBar --preview <folder>` renders the website/README screenshots and quits.
        if let folder = PreviewRenderer.requestedFolder {
            _state = State(initialValue: AppState(isPreview: true))
            DispatchQueue.main.async { PreviewRenderer.run(to: folder) }
            return
        }
        #endif
        _state = State(initialValue: AppState())
    }

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
