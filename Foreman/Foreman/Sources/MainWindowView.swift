import AppKit
import ForemanCore
import SwiftUI

/// The main window: repos in the sidebar, the selected repo's worker detail
/// on the right, global actions in the toolbar.
struct MainWindowView: View {
    let session: ForemanSession

    @State private var selection: RepoID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let repo = session.repos.first(where: { $0.id == selection }) {
                WorkerDetailView(repo: repo)
                    // Reset the detail's local state (options draft, log
                    // tail) when the selection changes.
                    .id(repo.id)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "hammer",
                    description: Text("Pick a repo to inspect and control its worker."),
                )
            }
        }
        .frame(minWidth: 680, minHeight: 420)
        .safeAreaInset(edge: .top, spacing: 0) { issueBanner }
        .toolbar { toolbarContent }
        // First-open scan; later opens rescan via the window delegate's
        // windowDidBecomeKey (see AppDelegate). No file watching.
        .onAppear {
            session.rescan()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            // Enabled repos on top, disabled below, favorites floated to the
            // top of each section (ordering computed in ForemanCore).
            ForEach(session.repoSections) { section in
                Section(title(for: section.kind)) {
                    ForEach(section.repos) { repo in
                        WorkerRowView(repo: repo)
                            .tag(repo.id)
                    }
                }
            }
        }
        .overlay {
            if session.repos.isEmpty {
                ContentUnavailableView {
                    Label("No Git Repositories", systemImage: "folder.badge.questionmark")
                } description: {
                    Text(session.settings.resolvedScanDirectory.path)
                }
            }
        }
        .navigationTitle("Foreman")
    }

    private func title(for kind: RepoSection.Kind) -> String {
        switch kind {
            case .enabled: "Enabled"
            case .disabled: "Disabled"
        }
    }

    @ViewBuilder
    private var issueBanner: some View {
        if let issue = session.issueMessage {
            Label(issue, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if session.isInhibitingSleep {
            ToolbarItem {
                Label("Preventing sleep", systemImage: "moon.zzz.fill")
                    .help("The Mac won't idle-sleep while workers are running.")
            }
        }
        ToolbarItem {
            Button {
                session.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .help("Re-scan the development directory for repositories.")
        }
        ToolbarItem {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Change the scan directory or the cursor-agent executable.")
        }
        ToolbarItem {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .help("Quit Foreman and stop all workers.")
        }
    }
}

#if DEBUG
    #Preview {
        MainWindowView(session: PreviewSupport.populatedSession())
    }
#endif
