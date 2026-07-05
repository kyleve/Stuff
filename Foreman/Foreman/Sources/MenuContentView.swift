import AppKit
import ForemanCore
import SwiftUI

/// The menu bar window: the worker list, with the per-repo options editor and
/// the settings form as pushed screens.
struct MenuContentView: View {
    /// Which surface the window shows. One value, so the list, an options
    /// editor, and settings can't be visible at once.
    private enum Screen {
        case list
        case options(WorkerRow)
        case settings
    }

    let session: ForemanSession

    @State private var screen: Screen = .list

    var body: some View {
        Group {
            switch screen {
                case .list:
                    workerList
                case let .options(row):
                    WorkerOptionsView(session: session, repo: row.repo) {
                        screen = .list
                    }
                case .settings:
                    SettingsView(session: session) {
                        screen = .list
                    }
            }
        }
        .frame(width: 340)
        // First-open scan; subsequent opens rescan via the window delegate's
        // windowDidBecomeKey (see AppDelegate), which regular windows post
        // reliably. No file watching.
        .onAppear {
            session.rescan()
        }
    }

    private var workerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let issue = session.issueMessage {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding([.horizontal, .top], 12)
            }

            if session.rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(session.rows) { row in
                            WorkerRowView(session: session, row: row) {
                                screen = .options(row)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 420)
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("Foreman")
                .font(.headline)
            Spacer()
            if session.isInhibitingSleep {
                Label("Preventing sleep", systemImage: "moon.zzz.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("The Mac won't idle-sleep while workers are running.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No git repositories found")
                .font(.callout)
            Text(session.configuration.resolvedScanDirectory.path)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack {
            Button {
                session.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .help("Re-scan the development directory for repositories.")

            Spacer()

            Button {
                screen = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .help("Quit Foreman and stop all workers.")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

#if DEBUG
    #Preview {
        MenuContentView(session: PreviewSupport.emptySession())
    }
#endif
