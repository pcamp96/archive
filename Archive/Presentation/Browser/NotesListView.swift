import SwiftUI

struct NotesListView: View {
    @Bindable var session: WorkspaceSession

    var body: some View {
        List(selection: selectedNoteBinding) {
            ForEach(session.filteredNotes) { note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(note.title)
                            .font(.body.weight(.medium))

                        if let status = note.propertyValues["status"]?.stringValue,
                           status.isEmpty == false {
                            MetadataChip(title: status, prominence: .secondary)
                        }
                    }

                    if note.bodyPreview.isEmpty == false {
                        Text(note.bodyPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(note.relativePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .tag(note.id)
            }
        }
        .onChange(of: session.browserState.selectedNoteID) { _, noteID in
            guard let noteID,
                  let summary = session.filteredNotes.first(where: { $0.id == noteID }) ?? session.notes.first(where: { $0.id == noteID }) else {
                return
            }
            session.openNote(summary)
        }
    }

    private var selectedNoteBinding: Binding<NoteID?> {
        Binding(
            get: { session.browserState.selectedNoteID },
            set: { session.browserState.selectedNoteID = $0 }
        )
    }
}
