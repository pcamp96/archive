import SwiftUI

struct MetadataChip: View {
    enum Prominence {
        case primary
        case secondary
    }

    let title: String
    let prominence: Prominence

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
    }

    private var foregroundColor: Color {
        switch prominence {
        case .primary:
            return .accentColor
        case .secondary:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch prominence {
        case .primary:
            return .accentColor.opacity(0.16)
        case .secondary:
            return .secondary.opacity(0.12)
        }
    }
}
