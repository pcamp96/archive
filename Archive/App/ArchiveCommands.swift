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
            Button("Save Now") {
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

        CommandMenu("Editor") {
            Picker("Markdown Display", selection: Binding(
                get: { session.appSettings.markdownDisplayMode },
                set: { session.appSettings.markdownDisplayMode = $0 }
            )) {
                ForEach(MarkdownDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
    }
}
