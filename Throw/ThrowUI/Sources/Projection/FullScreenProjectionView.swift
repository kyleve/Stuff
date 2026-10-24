import SFSafeSymbols
import SnapshotKit
import SwiftUI
import UIKit

public struct FullScreenProjectionView: View {
    private let session: ThrowSession
    private let outputID: ProjectionOutputID
    private let onExit: () -> Void

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
            Button(String(localized: .projectionExit), systemSymbol: .xmark, action: onExit)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.black.opacity(0.7))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .background(.black)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onExit)
        .onAppear {
            session.projectionOutputConnected(.fullScreen(outputID))
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .onDisappear {
            session.projectionOutputDisconnected(.fullScreen(outputID))
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
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
