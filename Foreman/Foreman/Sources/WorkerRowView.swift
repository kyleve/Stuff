import ForemanCore
import SwiftUI

/// One repo in the sidebar: status dot, name, and the worker toggle. Detail
/// and actions live in `WorkerDetailView`.
struct WorkerRowView: View {
    let session: ForemanSession
    @Bindable var row: WorkerRow

    var body: some View {
        let state = session.workerState(for: row.repo)

        HStack(spacing: 8) {
            StatusDot(state: state)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.repo.name)
                if case .failed = state {
                    Text("Failed — see detail")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Toggle("Worker enabled", isOn: $row.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
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
            case let .running(pid, _): "Running (pid \(pid))"
            case .stopping(restartPending: true): "Restarting…"
            case .stopping(restartPending: false): "Stopping…"
            case let .failed(reason): "Failed: \(reason)"
        }
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.populatedSession()
        return List {
            ForEach(session.rows) { row in
                WorkerRowView(session: session, row: row)
            }
        }
        .frame(width: 240, height: 200)
    }
#endif
