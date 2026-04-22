import SwiftUI

struct NotesBrowserView: View {
    @Bindable var session: WorkspaceSession
    @State private var isShowingStatusesSheet = false

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
        .contextMenu {
            Button("New Note", systemImage: "plus") {
                Task {
                    await session.createNote(in: session.selectedFolderURL ?? session.rootURL)
                }
            }
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

                    if let editableBoardPropertyName {
                        Button("\(editableBoardPropertyName.capitalized)…") {
                            isShowingStatusesSheet = true
                        }
                    }
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
        .sheet(isPresented: $isShowingStatusesSheet) {
            if let editableBoardPropertyName {
                StatusOptionsSheet(
                    propertyName: editableBoardPropertyName,
                    options: session.propertyRegistry.definition(for: editableBoardPropertyName)?.options ?? []
                ) { options in
                    Task {
                        await session.updatePropertyDefinitionOptions(for: editableBoardPropertyName, options: options)
                    }
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
            set: { newValue in
                Task {
                    await session.updatePresentationMode(newValue)
                }
            }
        )
    }

    private var boardSelectionBinding: Binding<UUID> {
        Binding(
            get: { session.activeBoardView?.id ?? session.viewPreferences.savedBoardViews.first?.id ?? UUID() },
            set: { newValue in
                Task {
                    await session.updateBoardSelection(newValue)
                }
            }
        )
    }

    private var editableBoardPropertyName: String? {
        guard let activeBoardView = session.activeBoardView,
              session.propertyRegistry.definition(for: activeBoardView.groupByProperty)?.kind == .singleSelect else {
            return nil
        }
        return activeBoardView.groupByProperty
    }

    private var defaultWorkflowState: PropertyCreationState {
        PropertyCreationState(
            key: "status",
            kind: .singleSelect,
            optionsText: "Idea, Draft, In Review, Ready, Published"
        )
    }
}

private struct StatusOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let propertyName: String
    let save: ([String]) -> Void

    @State private var optionsText: String

    init(propertyName: String, options: [String], save: @escaping ([String]) -> Void) {
        self.propertyName = propertyName
        self.save = save
        _optionsText = State(initialValue: options.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit \(propertyDisplayName)")
                .font(.title2.weight(.semibold))

            Text("Update the lane order and suggested values for \(propertyName). Existing notes keep their current status until you change them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(propertyDisplayName)
                    .font(.subheadline.weight(.medium))
                TextField("Comma-separated values", text: $optionsText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save(
                        optionsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { $0.isEmpty == false }
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var propertyDisplayName: String {
        propertyName.capitalized
    }
}
