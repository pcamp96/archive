import SwiftUI

struct NotesBoardView: View {
    @Bindable var session: WorkspaceSession

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(session.boardColumns) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(column.title)
                            .font(.headline)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(column.notes) { note in
                                    Button {
                                        session.browserState.selectedNoteID = note.id
                                        session.openNote(note)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(note.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            if note.bodyPreview.isEmpty == false {
                                                Text(note.bodyPreview)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(3)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .draggable(note.id.id)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(width: 260, alignment: .topLeading)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .dropDestination(for: String.self) { ids, _ in
                        guard let first = ids.first,
                              let note = session.notes.first(where: { $0.id.id == first }) else { return false }
                        Task {
                            await session.moveNote(note, toBoardValue: column.key)
                        }
                        return true
                    }
                }
            }
            .padding()
        }
    }
}

