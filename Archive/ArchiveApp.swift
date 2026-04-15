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
                    Task {
                        switch newValue {
                        case .active:
                            await container.appSession.refreshActiveWorkspace()
                        case .inactive, .background:
                            await container.appSession.workspaceSession?.flushActiveNote()
                        @unknown default:
                            break
                        }
                    }
                }
        }
        .commands {
            ArchiveCommands(session: container.appSession)
        }

        Settings {
            SettingsView(settings: container.appSettings)
        }
    }
}
