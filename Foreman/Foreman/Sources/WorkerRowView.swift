import AppKit
import ForemanCore
import SwiftUI

/// One repo in the menu: status dot, name, worker toggle, and the options /
/// log affordances.
struct WorkerRowView: View {
    let session: ForemanSession
    @Bindable var row: WorkerRow
    let onEditOptions: () -> Void

    var body: some View {
        let state = session.workerState(for: row.repo)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                StatusDot(state: state)

                Toggle(isOn: $row.isEnabled) {
                    Text(row.repo.name)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                Button {
                    NSWorkspace.shared.open(session.logFileURL(for: row.repo))
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Open this worker's log.")

                Button(action: onEditOptions) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .disabled(state.isLive)
                .help(
                    state.isLive
                        ? "Stop the worker to edit its options."
                        : "Edit this worker's options.",
                )
            }

            if case let .failed(reason) = state {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

/// The colored liveness indicator for one worker.
struct StatusDot: View {
    let state: WorkerSupervisor.WorkerState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(help)
    }

    private var color: Color {
        switch state {
            case .stopped: .secondary.opacity(0.4)
            case .stopping: .yellow
            case .running: .green
            case .failed: .red
        }
    }

    private var help: String {
        switch state {
            case .stopped: "Stopped"
            case let .running(pid): "Running (pid \(pid))"
            case .stopping(restartPending: true): "Restarting…"
            case .stopping(restartPending: false): "Stopping…"
            case let .failed(reason): "Failed: \(reason)"
        }
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.populatedSession()
        return VStack(spacing: 0) {
            ForEach(session.rows) { row in
                WorkerRowView(session: session, row: row) {}
            }
        }
        .frame(width: 340)
        .padding(.vertical)
    }
#endif
