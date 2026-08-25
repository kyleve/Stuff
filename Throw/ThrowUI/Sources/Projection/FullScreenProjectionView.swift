import SFSafeSymbols
import SwiftUI

public struct FullScreenProjectionView: View {
    private let session: ThrowSession
    private let outputID: ProjectionOutputID
    private let onExit: () -> Void

    @State private var controlsVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onAppear { session.projectionOutputConnected(.fullScreen(outputID)) }
        .onDisappear { session.projectionOutputDisconnected(.fullScreen(outputID)) }
        .task(id: controlsVisible) {
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
        guard controlsVisible else { return }
        do {
            try await Task.sleep(for: .seconds(4))
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("Unexpected projection-control timer failure: \(error)")
            return
        }
        guard Task.isCancelled == false else { return }
        controlsVisible = false
    }
}
