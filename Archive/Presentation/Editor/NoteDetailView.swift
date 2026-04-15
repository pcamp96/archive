import AppKit
import SwiftUI

struct NoteDetailView: View {
    @Bindable var workspaceSession: WorkspaceSession
    @Bindable var editorSession: EditorSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Title", text: $editorSession.draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .semibold, design: .serif))

                    PropertiesInspectorView(
                        properties: $editorSession.draft.properties,
                        registry: workspaceSession.propertyRegistry
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Markdown")
                            .font(.headline)
                        MarkdownTextView(
                            text: $editorSession.draft.body,
                            selectedText: $editorSession.selectedMarkdownText
                        )
                        .frame(minHeight: 420)
                    }

                    if let conflictMessage = editorSession.conflictMessage {
                        Text(conflictMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(24)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Save") {
                    Task {
                        await workspaceSession.saveActiveNote()
                    }
                }
                .keyboardShortcut("s")

                Button("Copy") {
                    editorSession.copyMarkdownSelection()
                }

                Button("Copy as HTML") {
                    editorSession.copyHTMLSelection()
                }

                Menu("File") {
                    Button("Rename…") {
                        promptRename()
                    }
                    Button("Move…") {
                        promptMove()
                    }
                    Divider()
                    Button("Delete") {
                        Task {
                            await workspaceSession.deleteCurrentNote()
                        }
                    }
                }
            }
        }
    }

    private func promptRename() {
        guard let summary = workspaceSession.currentNoteSummary else { return }
        let panel = NSSavePanel()
        panel.title = "Rename Note"
        panel.directoryURL = summary.fileURL.deletingLastPathComponent()
        panel.nameFieldStringValue = summary.fileURL.deletingPathExtension().lastPathComponent
        panel.canCreateDirectories = false
        panel.allowedContentTypes = []
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK else { return }
        let proposedName = panel.nameFieldStringValue
        Task {
            await workspaceSession.renameCurrentNote(to: proposedName)
        }
    }

    private func promptMove() {
        let panel = NSOpenPanel()
        panel.title = "Move Note"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            await workspaceSession.moveCurrentNote(to: destination)
        }
    }
}

