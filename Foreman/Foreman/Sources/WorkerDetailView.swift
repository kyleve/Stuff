import AppKit
import ForemanCore
import SwiftUI

/// Everything about one repo's worker: status, the command it runs, its
/// options, and a live log tail.
struct WorkerDetailView: View {
    let session: ForemanSession
    @Bindable var row: WorkerRow

    var body: some View {
        let state = session.workerState(for: row.repo)

        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        StatusDot(state: state)
                        Text(statusText(for: state))
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
                    Text(row.repo.rootURL.path).textSelection(.enabled)
                }
                Toggle("Worker enabled", isOn: $row.isEnabled)
            }

            Section("Command") {
                // What the next start will spawn (options apply at spawn).
                Text(commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            WorkerOptionsView(session: session, repo: row.repo, isLocked: state.isLive)

            Section {
                WorkerLogView(url: session.logFileURL(for: row.repo))
            } header: {
                HStack {
                    Text("Log")
                    Spacer()
                    Button("Open File") {
                        NSWorkspace.shared.open(session.logFileURL(for: row.repo))
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(row.repo.name)
        .navigationSubtitle(row.repo.rootURL.path)
    }

    private func statusText(for state: WorkerSupervisor.WorkerState) -> String {
        switch state {
            case .stopped: "Stopped"
            case .running: "Running"
            case .stopping(restartPending: true): "Restarting…"
            case .stopping(restartPending: false): "Stopping…"
            case .failed: "Failed"
        }
    }

    private var commandPreview: String {
        let arguments = session.configuration
            .options(for: row.repo.id)
            .arguments(workerDirectory: row.repo.rootURL)
        return (["cursor-agent"] + arguments).joined(separator: " ")
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.populatedSession()
        return WorkerDetailView(session: session, row: session.rows[0])
            .frame(width: 460, height: 640)
    }
#endif
