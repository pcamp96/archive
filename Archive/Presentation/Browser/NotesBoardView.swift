import SwiftUI

struct NotesBoardView: View {
    @Bindable var session: WorkspaceSession
    let boardView: SavedBoardView

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(session.boardColumns) { column in
                    BoardColumnView(session: session, boardView: boardView, column: column)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

private struct BoardColumnView: View {
    @Bindable var session: WorkspaceSession
    let boardView: SavedBoardView
    let column: BoardColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(column.title)
                    .font(.headline)
                Spacer()
                Text("\(column.notes.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(column.notes) { note in
                        BoardCardView(note: note, boardView: boardView) {
                            session.browserState.selectedNoteID = note.id
                            session.openNote(note)
                        }
                        .draggable(note.id.id)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 288, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in
            guard let first = ids.first,
                  let note = session.notes.first(where: { $0.id.id == first }) else {
                return false
            }

            Task {
                await session.moveNote(note, toBoardValue: column.key)
            }
            return true
        }
    }
}

private struct BoardCardView: View {
    let note: NoteSummary
    let boardView: SavedBoardView
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                Text(note.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if note.bodyPreview.isEmpty == false {
                    Text(note.bodyPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let primaryChipTitle {
                    MetadataChip(title: primaryChipTitle, prominence: .primary)
                }

                if secondaryChipTitles.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(secondaryChipTitles, id: \.self) { title in
                            MetadataChip(title: title, prominence: .secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var primaryChipTitle: String? {
        guard let value = note.propertyValues[boardView.groupByProperty]?.stringValue,
              value.isEmpty == false else {
            return nil
        }
        return value
    }

    private var secondaryChipTitles: [String] {
        note.propertyValues
            .filter { key, value in
                key != boardView.groupByProperty && value.stringValue.isEmpty == false
            }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .prefix(2)
            .map { entry in
                "\(entry.key.capitalized): \(entry.value.stringValue)"
            }
    }
}
