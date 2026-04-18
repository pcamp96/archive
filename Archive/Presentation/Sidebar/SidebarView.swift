import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var session: WorkspaceSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let folderTree = session.folderTree {
                    Text("Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FolderNodeView(
                        session: session,
                        node: folderTree,
                        selectedFolderURL: Binding(
                            get: { session.browserState.selectedFolderURL },
                            set: { session.browserState.selectedFolderURL = $0 }
                        )
                    )
                }
            }
        }
        .padding(12)
        .contextMenu {
            Button("New Note") {
                Task {
                    await session.createNote(in: session.selectedFolderURL ?? session.rootURL)
                }
            }
            Button("New Folder…") {
                promptForFolder(in: session.selectedFolderURL ?? session.rootURL)
            }
        }
        .navigationTitle(session.rootURL.lastPathComponent)
    }

    private func promptForFolder(in parentURL: URL) {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Choose a name for the new folder."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }

        Task {
            await session.createFolder(named: name, in: parentURL)
        }
    }
}

private struct FolderNodeView: View {
    @Bindable var session: WorkspaceSession
    let node: FolderNode
    @Binding var selectedFolderURL: URL?
    @State private var isExpanded: Bool

    init(session: WorkspaceSession, node: FolderNode, selectedFolderURL: Binding<URL?>) {
        self.session = session
        self.node = node
        self._selectedFolderURL = selectedFolderURL
        _isExpanded = State(initialValue: FolderNodeView.shouldExpand(node: node, selectedFolderURL: selectedFolderURL.wrappedValue))
    }

    var body: some View {
        Group {
            if node.children.isEmpty {
                SidebarFolderButton(
                    title: node.name,
                    systemImage: selectedFolderURL == node.url ? "folder.fill" : "folder",
                    isSelected: selectedFolderURL == node.url,
                    action: { selectedFolderURL = node.url }
                )
                .contextMenu {
                    folderContextMenu
                }
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(node.children) { child in
                            FolderNodeView(session: session, node: child, selectedFolderURL: $selectedFolderURL)
                        }
                    }
                    .padding(.leading, 12)
                } label: {
                    SidebarFolderButton(
                        title: node.name,
                        systemImage: selectedFolderURL == node.url ? "folder.fill" : "folder",
                        isSelected: selectedFolderURL == node.url,
                        action: { selectedFolderURL = node.url }
                    )
                }
                .contextMenu {
                    folderContextMenu
                }
            }
        }
        .onChange(of: selectedFolderURL) { _, newValue in
            if Self.shouldExpand(node: node, selectedFolderURL: newValue) {
                isExpanded = true
            }
        }
    }

    @ViewBuilder
    private var folderContextMenu: some View {
        Button("New Note") {
            selectedFolderURL = node.url
            Task {
                await session.createNote(in: node.url)
            }
        }
        Button("New Folder…") {
            selectedFolderURL = node.url
            promptForFolder(in: node.url)
        }
    }

    private func promptForFolder(in parentURL: URL) {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Choose a name for the new folder."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }

        Task {
            await session.createFolder(named: name, in: parentURL)
        }
    }

    private static func shouldExpand(node: FolderNode, selectedFolderURL: URL?) -> Bool {
        guard let selectedFolderURL else { return false }

        let nodePath = node.url.standardizedFileURL.path
        let selectedPath = selectedFolderURL.standardizedFileURL.path
        return selectedPath == nodePath || selectedPath.hasPrefix(nodePath + "/")
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
