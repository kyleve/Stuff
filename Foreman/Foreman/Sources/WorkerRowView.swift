import ForemanCore
import SwiftUI

/// One repo in the sidebar: status dot, name, and the worker toggle. Detail
/// and actions live in `WorkerDetailView`.
struct WorkerRowView: View {
    @Bindable var repo: Repo

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: repo.worker.state)

            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                if case .failed = repo.worker.state {
                    Text(.rowFailed)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if repo.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .help(.rowFavoriteHelp)
            }

            Spacer()

            Toggle(.workerEnabledToggle, isOn: $repo.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(
                repo.isFavorite ? .favoriteRemove : .favoriteAdd,
                systemImage: repo.isFavorite ? "star.slash" : "star",
            ) {
                repo.isFavorite.toggle()
            }
        }
    }
}

/// The colored liveness indicator for one worker.
struct StatusDot: View {
    let state: Worker.State

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

    private var help: LocalizedStringResource {
        switch state {
            case .stopped: .statusStopped
            case let .running(pid, _): .statusRunningPid(pid: Int(pid))
            case .stopping(restartPending: true): .statusRestarting
            case .stopping(restartPending: false): .statusStopping
            case let .failed(reason): .statusFailedReason(reason: reason)
        }
    }
}

#if DEBUG
    #Preview {
        let session = PreviewSupport.populatedSession()
        return List {
            ForEach(session.repos) { repo in
                WorkerRowView(repo: repo)
            }
        }
        .frame(width: 240, height: 200)
    }
#endif
