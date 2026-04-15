import SwiftUI

struct WorkspaceSplitView: View {
    @Bindable var session: WorkspaceSession

    var body: some View {
        NavigationSplitView {
            SidebarView(session: session)
        } content: {
            NotesBrowserView(session: session)
        } detail: {
            if let editorSession = session.editorSession {
                NoteDetailView(workspaceSession: session, editorSession: editorSession)
            } else {
                EmptyStateView(
                    title: "Select a Note",
                    message: "Choose a markdown note from the list or create a new one to start writing."
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottomTrailing) {
            if session.isLoading {
                ProgressView()
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }
}

