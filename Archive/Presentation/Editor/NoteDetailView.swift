import SwiftUI

struct NoteDetailView: View {
    @Bindable var workspaceSession: WorkspaceSession
    @Bindable var editorSession: EditorSession

    @State private var isShowingPropertySheet = false

    private struct AutosaveTaskID: Hashable {
        let noteID: NoteID
        let nonce: Int
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack {
                Spacer(minLength: 24)
                EditorialNoteSurface(
                    title: titleBinding,
                    autosaveState: editorSession.autosaveState,
                    headerContextMenu: {
                        if let note = workspaceSession.currentEditorNoteSummary {
                            NoteContextMenuContent(session: workspaceSession, note: note, showsOpenAction: false)
                        }
                    },
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
                .frame(maxWidth: 940, maxHeight: .infinity, alignment: .topLeading)
                Spacer(minLength: 24)
            }
            .padding(.vertical, 22)
        }
        .toolbar {
            NoteToolbarActionGroup(
                session: workspaceSession,
                editorSession: editorSession,
                effectiveDisplayMode: effectiveDisplayMode,
                displayModeBinding: displayModeBinding
            )
        }
        .task(id: AutosaveTaskID(noteID: editorSession.noteID, nonce: editorSession.autosaveNonce)) {
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
}

private struct EditorialNoteSurface<HeaderContextMenu: View, PropertiesContent: View, EditorContent: View>: View {
    @Binding var title: String
    let autosaveState: AutosaveState
    @ViewBuilder let headerContextMenu: () -> HeaderContextMenu
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
            .contextMenu(menuItems: headerContextMenu)

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
