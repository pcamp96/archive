import AppKit
import SwiftUI

struct NoteContextMenuContent: View {
    @Bindable var session: WorkspaceSession
    let note: NoteSummary
    var showsOpenAction = true

    var body: some View {
        if showsOpenAction {
            Button("Open", systemImage: "arrow.up.right.square") {
                session.revealNote(note)
            }
        }

        Button("Show in Finder", systemImage: "folder") {
            session.revealNoteInFinder(note)
        }

        Button("Copy Relative Path", systemImage: "link") {
            session.copyRelativePath(for: note)
        }

        Divider()

        Button("Rename…", systemImage: "pencil") {
            guard let filename = NoteActionPrompts.promptRename(for: note) else { return }
            Task {
                await session.renameNote(note, to: filename)
            }
        }

        Button("Move…", systemImage: "folder.badge.gearshape") {
            guard let folderURL = NoteActionPrompts.promptMove() else { return }
            Task {
                await session.moveNote(note, to: folderURL)
            }
        }

        Divider()

        Button("Delete", systemImage: "trash", role: .destructive) {
            Task {
                await session.deleteNote(note)
            }
        }
    }
}

struct NoteToolbarActionGroup: ToolbarContent {
    @Bindable var session: WorkspaceSession
    @Bindable var editorSession: EditorSession
    let effectiveDisplayMode: MarkdownDisplayMode
    let displayModeBinding: Binding<MarkdownDisplayMode>

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("Copy Selection as Markdown", systemImage: "doc.on.doc") {
                    editorSession.copyMarkdownSelection()
                }

                Button("Copy Selection as HTML", systemImage: "curlybraces") {
                    editorSession.copyHTMLSelection()
                }
            } label: {
                ToolbarMenuLabel(title: "Copy", systemImage: "doc.on.doc")
            }

            Menu {
                Picker("Editor Mode", selection: displayModeBinding) {
                    ForEach(MarkdownDisplayMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImageName)
                            .tag(mode)
                    }
                }

                if editorSession.displayModeOverride != nil {
                    Divider()
                    Button("Use Workspace Default", systemImage: "arrow.uturn.backward") {
                        editorSession.displayModeOverride = nil
                    }
                }
            } label: {
                ToolbarMenuLabel(
                    title: "Display",
                    systemImage: effectiveDisplayMode.systemImageName
                )
            }

            if let note = session.currentEditorNoteSummary {
                Menu {
                    NoteContextMenuContent(session: session, note: note, showsOpenAction: false)
                } label: {
                    ToolbarMenuLabel(title: "Note", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

enum NoteActionPrompts {
    @MainActor
    static func promptRename(for note: NoteSummary) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename Note"
        alert.informativeText = "Choose a new filename for this note."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = note.fileURL.deletingPathExtension().lastPathComponent
        field.selectText(nil)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    @MainActor
    static func promptMove() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Move Note"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

private struct ToolbarMenuLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }
}

private extension MarkdownDisplayMode {
    var systemImageName: String {
        switch self {
        case .markdownOnly:
            return "text.alignleft"
        case .hybrid:
            return "textformat.abc"
        case .markupOnly:
            return "doc.plaintext"
        }
    }
}
