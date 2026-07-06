import AppKit
import ForemanCore
import SwiftUI

/// Everything about one repo's worker: status, the command it runs, its
/// options, and a live log tail.
struct WorkerDetailView: View {
    @Bindable var repo: Repo

    var body: some View {
        let state = repo.worker.state

        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        StatusDot(state: state)
                        Text(statusText(for: state))
                        statusActions
                    }
                }
                if case let .running(pid, since) = state {
                    LabeledContent("PID") {
                        Text(String(pid)).textSelection(.enabled)
                    }
                    LabeledContent("Uptime") {
                        Text(since, style: .relative)
                    }
                }
                if case let .failed(reason) = state {
                    LabeledContent("Failure") {
                        Text(reason).foregroundStyle(.red)
                    }
                }
                LabeledContent("Path") {
                    Text(repo.rootURL.path).textSelection(.enabled)
                }
                Toggle("Worker enabled", isOn: $repo.isEnabled)
            }

            Section("Command") {
                // What the next start will spawn (options apply at spawn).
                Text(commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            WorkerOptionsView(repo: repo, isLocked: state.isLive)

            Section {
                WorkerLogView(url: repo.worker.logFileURL)
            } header: {
                HStack {
                    Text("Log")
                    Spacer()
                    Button("Open File") {
                        NSWorkspace.shared.open(repo.worker.logFileURL)
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(repo.name)
        .navigationSubtitle(repo.rootURL.path)
        .toolbar {
            ToolbarItem {
                Button {
                    repo.isFavorite.toggle()
                } label: {
                    Label(
                        repo.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: repo.isFavorite ? "star.fill" : "star",
                    )
                }
                .help(repo.isFavorite
                    ? "Remove this repo from favorites."
                    : "Pin this repo to the top of its section.")
            }
        }
    }

    /// The transient actions the enable toggle can't express, shown only in
    /// the states where they apply. Both are `Repo` intents — they respawn
    /// without touching the persisted desired state.
    @ViewBuilder
    private var statusActions: some View {
        switch repo.worker.state {
            case .failed:
                if repo.isEnabled {
                    Button("Retry") {
                        repo.retry()
                    }
                    .controlSize(.small)
                    .help("Try starting the worker again.")
                }
            case .running:
                Button("Restart") {
                    repo.restart()
                }
                .controlSize(.small)
                .help("Stop the worker and start it again with the saved options.")
            case .stopped, .stopping:
                EmptyView()
        }
    }

    private func statusText(for state: Worker.State) -> String {
        switch state {
            case .stopped: "Stopped"
            case .running: "Running"
            case .stopping(restartPending: true): "Restarting…"
            case .stopping(restartPending: false): "Stopping…"
            case .failed: "Failed"
        }
    }

    private var commandPreview: String {
        let arguments = repo.options.arguments(workerDirectory: repo.rootURL)
        return (["cursor-agent"] + arguments).joined(separator: " ")
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.populatedSession()
        return WorkerDetailView(repo: session.repos[0])
            .frame(width: 460, height: 640)
    }
#endif
