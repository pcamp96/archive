import SwiftUI

struct SidebarView: View {
    @Bindable var session: WorkspaceSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SidebarFolderButton(
                    title: "All Notes",
                    systemImage: "square.stack",
                    isSelected: session.selectedFolderURL == session.rootURL,
                    action: { session.selectedFolderURL = session.rootURL }
                )

                if let folderTree = session.folderTree {
                    Text("Folders")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)

                    FolderNodeView(
                        node: folderTree,
                        selectedFolderURL: Binding(
                            get: { session.browserState.selectedFolderURL },
                            set: { session.browserState.selectedFolderURL = $0 }
                        )
                    )
                    .padding(.leading, 6)
                }
            }
        }
        .padding(12)
        .navigationTitle(session.rootURL.lastPathComponent)
    }
}

private struct FolderNodeView: View {
    let node: FolderNode
    @Binding var selectedFolderURL: URL?

    var body: some View {
        DisclosureGroup {
            ForEach(node.children) { child in
                FolderNodeView(node: child, selectedFolderURL: $selectedFolderURL)
            }
        } label: {
            Button {
                selectedFolderURL = node.url
            } label: {
                Label(node.name, systemImage: "folder")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SidebarFolderButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.secondary.opacity(0.15) : Color.clear)
                    )
        }
        .buttonStyle(.plain)
    }
}
