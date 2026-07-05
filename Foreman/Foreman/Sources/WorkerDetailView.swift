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
