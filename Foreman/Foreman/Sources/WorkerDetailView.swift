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
                LabeledContent(.detailStatusLabel) {
                    HStack(spacing: 8) {
                        StatusDot(state: state)
                        Text(statusText(for: state))
                        statusActions
                    }
                }
                if case let .running(pid, since) = state {
                    LabeledContent(.detailPidLabel) {
                        Text(String(pid)).textSelection(.enabled)
                    }
                    LabeledContent(.detailUptimeLabel) {
                        Text(since, style: .relative)
                    }
                }
                if case let .failed(reason) = state {
                    LabeledContent(.detailFailureLabel) {
                        Text(reason).foregroundStyle(.red)
                    }
                }
                LabeledContent(.detailPathLabel) {
                    Text(repo.rootURL.path).textSelection(.enabled)
                }
                Toggle(.workerEnabledToggle, isOn: $repo.isEnabled)
            }

            Section(.detailCommandHeader) {
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
                    Text(.detailLogHeader)
                    Spacer()
                    Button(.detailLogOpenFile) {
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
                        repo.isFavorite ? .favoriteRemove : .favoriteAdd,
                        systemImage: repo.isFavorite ? "star.fill" : "star",
                    )
                }
                .help(repo.isFavorite ? .favoriteRemoveHelp : .favoriteAddHelp)
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
                    Button(.detailActionRetry) {
                        repo.retry()
                    }
                    .controlSize(.small)
                    .help(.detailActionRetryHelp)
                }
            case .running:
                Button(.detailActionRestart) {
                    repo.restart()
                }
                .controlSize(.small)
                .help(.detailActionRestartHelp)
            case .stopped, .stopping:
                EmptyView()
        }
    }

    private func statusText(for state: Worker.State) -> LocalizedStringResource {
        switch state {
            case .stopped: .statusStopped
            case .running: .statusRunning
            case .stopping(restartPending: true): .statusRestarting
            case .stopping(restartPending: false): .statusStopping
            case .failed: .statusFailed
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
