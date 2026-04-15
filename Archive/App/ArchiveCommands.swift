import SwiftUI

struct ArchiveCommands: Commands {
    @Bindable var session: AppSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                session.createNote()
            }
            .keyboardShortcut("n")
            .disabled(session.workspaceSession == nil)

            Button("Open Workspace…") {
                session.promptForWorkspace()
            }
            .keyboardShortcut("o")
        }

        CommandMenu("Archive") {
            Button("Save Note") {
                session.saveCurrentNote()
            }
            .keyboardShortcut("s")
            .disabled(session.workspaceSession?.editorSession == nil)

            Button("Toggle List / Board") {
                session.switchPresentationMode()
            }
            .keyboardShortcut("b")
            .disabled(session.workspaceSession == nil)
        }
    }
}

