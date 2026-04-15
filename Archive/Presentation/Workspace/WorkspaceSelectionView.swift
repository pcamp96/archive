import SwiftUI

struct WorkspaceSelectionView: View {
    let recentWorkspaces: [RecentWorkspace]
    let onOpenWorkspace: () -> Void
    let onOpenRecent: (RecentWorkspace) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Archive")
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                Text("A local-first markdown workspace for structured writing.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Open Workspace…", action: onOpenWorkspace)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            if recentWorkspaces.isEmpty == false {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Workspaces")
                        .font(.headline)
                    ForEach(recentWorkspaces) { workspace in
                        Button {
                            onOpenRecent(workspace)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workspace.displayName)
                                    .font(.body.weight(.medium))
                                Text(workspace.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

