import SwiftUI

struct NotesBrowserView: View {
    @Bindable var session: WorkspaceSession

    var body: some View {
        Group {
            switch session.browserState.presentationMode {
            case .list:
                listContent
            case .board:
                boardContent
            }
        }
        .navigationTitle(columnTitle)
        .searchable(text: $session.browserState.searchQuery, prompt: "Search notes")
        .task(id: session.browserState.searchQuery) {
            await session.refreshSearch()
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: presentationModeBinding) {
                    Label("List", systemImage: "list.bullet").tag(NotesPresentationMode.list)
                    Label("Board", systemImage: "square.grid.3x2").tag(NotesPresentationMode.board)
                }
                .pickerStyle(.segmented)

                if session.browserState.presentationMode == .board,
                   session.viewPreferences.savedBoardViews.isEmpty == false {
                    Picker("Board", selection: boardSelectionBinding) {
                        ForEach(session.viewPreferences.savedBoardViews) { boardView in
                            Text(boardView.name).tag(boardView.id)
                        }
                    }
                    .frame(width: 220)
                }

                Button {
                    Task {
                        await session.createNote()
                    }
                } label: {
                    Label("New Note", systemImage: "plus")
                }
            }
        }
    }

    private var columnTitle: String {
        if session.browserState.selectedFolderURL == session.rootURL || session.browserState.selectedFolderURL == nil {
            return "Notes"
        }
        return session.browserState.selectedFolderURL?.lastPathComponent ?? "Notes"
    }

    @ViewBuilder
    private var listContent: some View {
        if session.filteredNotes.isEmpty {
            EmptyStateView(
                title: "No Notes",
                message: "Create a markdown note in this workspace to populate the browser."
            )
        } else {
            NotesListView(session: session)
        }
    }

    @ViewBuilder
    private var boardContent: some View {
        if let activeBoardView = session.activeBoardView {
            NotesBoardView(session: session, boardView: activeBoardView)
        } else {
            ContentUnavailableView {
                Label("No Workflow Board Yet", systemImage: "square.grid.3x2")
            } description: {
                Text("Create a workflow property like status to organize notes into lanes.")
            } actions: {
                Button("Create Workflow Property") {
                    Task {
                        await session.createProperty(defaultWorkflowState, addToCurrentNote: false)
                    }
                }
            }
        }
    }

    private var presentationModeBinding: Binding<NotesPresentationMode> {
        Binding(
            get: { session.browserState.presentationMode },
            set: { session.updatePresentationMode($0) }
        )
    }

    private var boardSelectionBinding: Binding<UUID> {
        Binding(
            get: { session.activeBoardView?.id ?? session.viewPreferences.savedBoardViews.first?.id ?? UUID() },
            set: { session.updateBoardSelection($0) }
        )
    }

    private var defaultWorkflowState: PropertyCreationState {
        PropertyCreationState(
            key: "status",
            kind: .singleSelect,
            optionsText: "Idea, Draft, In Review, Ready, Published"
        )
    }
}
