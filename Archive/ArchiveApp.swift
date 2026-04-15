import SwiftUI

@main
struct ArchiveApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootContentView(session: container.appSession)
                .environment(container)
                .task {
                    await container.appSession.restoreLastWorkspaceIfPossible()
                }
                .onChange(of: scenePhase) { _, newValue in
                    guard newValue == .active else { return }
                    Task {
                        await container.appSession.refreshActiveWorkspace()
                    }
                }
        }
        .commands {
            ArchiveCommands(session: container.appSession)
        }

        Settings {
            SettingsView()
        }
    }
}

