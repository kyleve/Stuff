import SFSafeSymbols
import SnapshotKit
import SwiftUI
import UIKit

public struct FullScreenProjectionView: View {
    private let session: ThrowSession
    private let outputID: ProjectionOutputID
    private let onExit: () -> Void

    @State private var controlsVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    public init(
        session: ThrowSession,
        outputID: ProjectionOutputID,
        onExit: @escaping () -> Void,
    ) {
        self.session = session
        self.outputID = outputID
        self.onExit = onExit
    }

    public var body: some View {
        ZStack {
            ProjectionSurface(session: session, presentation: .fullScreen)
            Button(String(localized: .projectionShowControls), action: revealControls)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.clear)
                .contentShape(.rect)
                .accessibilityHidden(true)

            if controlsVisible {
                Button(String(localized: .projectionExit), systemSymbol: .xmark, action: onExit)
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.7))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(reduceMotion ? .opacity : .move(edge: .top)
                        .combined(with: .opacity))
            }
        }
        .background(.black)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: Text(.projectionExit), onExit)
        .onAppear {
            controlsVisible = true
            session.projectionOutputConnected(.fullScreen(outputID))
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .onDisappear {
            session.projectionOutputDisconnected(.fullScreen(outputID))
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .onChange(of: voiceOverEnabled) { _, isEnabled in
            if isEnabled {
                controlsVisible = true
            }
        }
        .task(id: controlAutoHideState) {
            await hideControlsAfterDelay()
        }
        .animation(
            reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.25),
            value: controlsVisible,
        )
    }

    private func revealControls() {
        controlsVisible = true
    }

    private func hideControlsAfterDelay() async {
        guard controlsVisible, voiceOverEnabled == false else { return }
        do {
            try await Task.sleep(for: .seconds(4))
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("Unexpected projection-control timer failure: \(error)")
            return
        }
        guard Task.isCancelled == false, voiceOverEnabled == false else { return }
        controlsVisible = false
    }

    private var controlAutoHideState: ControlAutoHideState {
        if voiceOverEnabled {
            return .disabled
        }
        return controlsVisible ? .scheduled : .idle
    }

    private enum ControlAutoHideState: Equatable {
        case idle
        case scheduled
        case disabled
    }
}

#if DEBUG
    extension FullScreenProjectionView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Initial Controls",
                configurations: [SnapshotConfiguration(device: .iPhone)],
                settle: .immediate,
            ) {
                FullScreenProjectionView(
                    session: .calibrationSnapshotFixture(),
                    outputID: ProjectionOutputID(rawValue: "snapshot-full-screen"),
                    onExit: {},
                )
                .throwBroadwayRoot()
            }
        }

        #Preview("Snapshot matrix") {
            FullScreenProjectionView.snapshotPreviews
        }
    }
#endif
