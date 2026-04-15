import AppKit
import SwiftUI

struct NoteDetailView: View {
    @Bindable var workspaceSession: WorkspaceSession
    @Bindable var editorSession: EditorSession

    @State private var isShowingPropertySheet = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack {
                Spacer(minLength: 28)
                EditorialNoteSurface(
                    title: titleBinding,
                    autosaveState: editorSession.autosaveState,
                    propertiesContent: {
                        if editorSession.draft.properties.isEmpty {
                            AddPropertyCallout(action: showPropertySheet)
                        } else {
                            PropertiesInspectorView(
                                properties: propertiesBinding,
                                registry: workspaceSession.propertyRegistry,
                                onChange: editorSession.markEdited,
                                onAddProperty: showPropertySheet
                            )
                        }
                    },
                    editorContent: {
                        MarkdownTextView(
                            text: bodyBinding,
                            selectedText: $editorSession.selectedMarkdownText,
                            displayMode: effectiveDisplayMode,
                            onEndEditing: flushNow
                        )
                    },
                    conflictMessage: editorSession.conflictMessage
                )
                .frame(maxWidth: 940, maxHeight: .infinity)
                Spacer(minLength: 28)
            }
            .padding(.vertical, 22)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Copy") {
                    editorSession.copyMarkdownSelection()
                }

                Menu("Display") {
                    Picker("Editor Mode", selection: displayModeBinding) {
                        ForEach(MarkdownDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if editorSession.displayModeOverride != nil {
                        Divider()
                        Button("Use Workspace Default") {
                            editorSession.displayModeOverride = nil
                        }
                    }
                }

                Menu("Note") {
                    Button("Copy as Markdown") {
                        editorSession.copyMarkdownSelection()
                    }
                    Button("Copy as HTML") {
                        editorSession.copyHTMLSelection()
                    }
                    Divider()
                    Button("Rename…", action: promptRename)
                    Button("Move…", action: promptMove)
                    Divider()
                    Button("Delete", role: .destructive) {
                        Task {
                            await workspaceSession.deleteCurrentNote()
                        }
                    }
                }
            }
        }
        .task(id: editorSession.autosaveNonce) {
            await workspaceSession.autosaveIfNeeded(for: editorSession)
        }
        .sheet(isPresented: $isShowingPropertySheet) {
            PropertyCreationSheet { state in
                Task {
                    await workspaceSession.createProperty(state, addToCurrentNote: true)
                }
            }
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { editorSession.draft.title },
            set: { newValue in
                guard editorSession.draft.title != newValue else { return }
                editorSession.draft.title = newValue
                editorSession.markEdited()
            }
        )
    }

    private var propertiesBinding: Binding<[EditableProperty]> {
        Binding(
            get: { editorSession.draft.properties },
            set: { newValue in
                guard editorSession.draft.properties != newValue else { return }
                editorSession.draft.properties = newValue
                editorSession.markEdited()
            }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { editorSession.draft.body },
            set: { newValue in
                guard editorSession.draft.body != newValue else { return }
                editorSession.draft.body = newValue
                editorSession.markEdited()
            }
        )
    }

    private var displayModeBinding: Binding<MarkdownDisplayMode> {
        Binding(
            get: { effectiveDisplayMode },
            set: { editorSession.displayModeOverride = $0 }
        )
    }

    private var effectiveDisplayMode: MarkdownDisplayMode {
        editorSession.displayModeOverride ?? workspaceSession.appSettings.markdownDisplayMode
    }

    private func showPropertySheet() {
        isShowingPropertySheet = true
    }

    private func flushNow() {
        Task {
            await workspaceSession.flushActiveNote()
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

private struct EditorialNoteSurface<PropertiesContent: View, EditorContent: View>: View {
    @Binding var title: String
    let autosaveState: AutosaveState
    @ViewBuilder let propertiesContent: () -> PropertiesContent
    @ViewBuilder let editorContent: () -> EditorContent
    let conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 34, weight: .bold, design: .serif))

                AutosaveBadge(state: autosaveState)
            }

            propertiesContent()

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            editorContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(30)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 34, y: 12)
    }
}

private struct AutosaveBadge: View {
    let state: AutosaveState

    var body: some View {
        Text(state.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor, in: Capsule())
    }

    private var foregroundStyle: Color {
        switch state {
        case .conflict, .error:
            return .orange
        case .saving:
            return .accentColor
        case .saved:
            return .secondary
        case .dirty:
            return .primary
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .conflict, .error:
            return .orange.opacity(0.14)
        case .saving:
            return .accentColor.opacity(0.12)
        case .saved:
            return .secondary.opacity(0.12)
        case .dirty:
            return .primary.opacity(0.10)
        }
    }
}

private struct AddPropertyCallout: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Add Property")
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
