import SwiftUI

struct NotesBrowserView: View {
    @Bindable var session: WorkspaceSession

    var body: some View {
        Group {
            if session.filteredNotes.isEmpty {
                EmptyStateView(
                    title: "No Notes",
                    message: "Create a markdown note in this workspace to populate the browser."
                )
            } else {
                switch session.browserState.presentationMode {
                case .list:
                    NotesListView(session: session)
                case .board:
                    NotesBoardView(session: session)
                }
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

                if session.browserState.presentationMode == .board {
                    Picker("Group By", selection: boardPropertyBinding) {
                        ForEach(session.propertyRegistry.orderedDefinitions.filter(\.isBoardEligible), id: \.key) { definition in
                            Text(definition.key).tag(definition.key)
                        }
                    }
                    .frame(width: 180)
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

    private var presentationModeBinding: Binding<NotesPresentationMode> {
        Binding(
            get: { session.browserState.presentationMode },
            set: { session.updatePresentationMode($0) }
        )
    }

    private var boardPropertyBinding: Binding<String> {
        Binding(
            get: { session.browserState.boardPropertyKey ?? session.propertyRegistry.defaultBoardPropertyKey ?? "status" },
            set: { session.updateBoardProperty($0) }
        )
    }
}

