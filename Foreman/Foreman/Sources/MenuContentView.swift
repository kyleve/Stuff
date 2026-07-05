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
    /// Bumped by the pump on every session change purely to force a body
    /// re-evaluation; see `startPumpIfNeeded`.
    @State private var refreshTick = 0
    @State private var pump: ObservationPump?

    var body: some View {
        // Deliberate read: ties this body to `refreshTick` so the pump's bump
        // re-evaluates it even when SwiftUI's own observation tracking is dead.
        let _ = refreshTick
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
        .onAppear {
            session.rescan()
            startPumpIfNeeded()
        }
        // Refresh the repo list whenever the panel becomes visible (no file
        // watching). Occlusion is the reliable "opened" signal here: the
        // panel doesn't necessarily become key, so key-window notifications
        // (and onAppear/controlActiveState, which don't re-fire per open on
        // this scene type) can't be the trigger. Fires for other windows too
        // — the redundant rescan is cheap and idempotent.
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification),
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  window.occlusionState.contains(.visible)
            else { return }
            session.rescan()
        }
    }

    /// Works around a `MenuBarExtra(.window)` defect: the panel content is
    /// built once at launch, `@Observable` mutations landing while the panel
    /// is closed (like the launch-time scan populating `rows`) are dropped,
    /// and — tracking being one-shot — the body then stops observing
    /// entirely, so nothing renders until a local `@State` change. The pump
    /// re-observes after every change and bumps `refreshTick`, whose `@State`
    /// invalidation doesn't depend on SwiftUI's observation at all.
    private func startPumpIfNeeded() {
        guard pump == nil else { return }
        pump = ObservationPump(
            tracking: {
                // Everything this view's hierarchy renders.
                for row in session.rows {
                    _ = row.isEnabled
                }
                _ = session.issueMessage
                _ = session.configuration
                _ = session.isInhibitingSleep
                _ = session.isAnyWorkerLive // registers the supervisor's states
            },
            onChange: { refreshTick += 1 },
        )
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
