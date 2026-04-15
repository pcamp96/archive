import SwiftUI

struct RootContentView: View {
    @Bindable var session: AppSession

    var body: some View {
        Group {
            if let workspaceSession = session.workspaceSession {
                WorkspaceSplitView(session: workspaceSession)
            } else {
                WorkspaceSelectionView(
                    recentWorkspaces: session.recentWorkspaces,
                    onOpenWorkspace: session.promptForWorkspace,
                    onOpenRecent: session.openRecentWorkspace
                )
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .alert(item: $session.presentedError) { presentedError in
            Alert(
                title: Text(presentedError.title),
                message: Text(presentedError.details),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

