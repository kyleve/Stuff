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
            // One flat ForEach — group headers and repo rows share a single
            // identity space — so a repo moving between the Enabled and
            // Disabled groups animates as one glide instead of a cross-Section
            // remove/insert. Ordering is computed in ForemanCore; the view
            // only flattens it into headers + rows and renders them.
            ForEach(sidebarRows) { row in
                switch row {
                    case let .header(kind):
                        Text(title(for: kind))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .selectionDisabled()
                    case let .repo(id, repo):
                        WorkerRowView(repo: repo)
                            .tag(id)
                }
            }
        }
        // Tween the diff whenever the flattened order changes — whatever the
        // trigger (enable toggle moving a repo across groups, favorite floating
        // it within one, or a rescan adding/removing repos).
        .animation(.snappy, value: sidebarRows.map(\.id))
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

    /// The sidebar's rows as one flat, stably-identified sequence: each
    /// non-empty section contributes a group header followed by its repos.
    /// A single identity space is what lets a repo glide across the group
    /// boundary rather than fade out of one section and into another.
    private var sidebarRows: [SidebarRow] {
        session.repoSections.flatMap { section in
            [SidebarRow.header(section.kind)] + section.repos.map { .repo(id: $0.id, repo: $0) }
        }
    }

    private func title(for kind: RepoSection.Kind) -> String {
        switch kind {
            case .enabled: "Enabled"
            case .disabled: "Disabled"
        }
    }

    /// One rendered sidebar entry — a group header or a repo — carried in a
    /// single `ForEach` so cross-group moves animate as a glide. Identity spans
    /// both kinds: a header keys off its section kind, a repo off its `RepoID`.
    ///
    /// The repo's `RepoID` is captured alongside the `Repo` so the nonisolated
    /// `Identifiable.id` getter needn't touch the `@MainActor`-isolated `Repo`.
    private enum SidebarRow: Identifiable {
        case header(RepoSection.Kind)
        case repo(id: RepoID, repo: Repo)

        enum ID: Hashable {
            case header(RepoSection.Kind)
            case repo(RepoID)
        }

        var id: ID {
            switch self {
                case let .header(kind): .header(kind)
                case let .repo(id, _): .repo(id)
            }
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
