import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct PreviewProjectionContainer: View {
    let session: ThrowSession
    let outputID: ProjectionOutputID
    let onExit: () -> Void

    var body: some View {
        PreviewProjectionView(session: session, outputID: outputID)
            .overlay(alignment: .topTrailing) {
                Button(String(localized: .commonDone), systemSymbol: .xmark, action: onExit)
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.7))
                    .padding()
            }
            .overlay(alignment: .bottom) {
                if session.experienceRotationHasControls {
                    HStack {
                        Button(
                            String(localized: .dashboardPreviousView),
                            systemSymbol: .backwardFill,
                        ) {
                            Task(name: "Throw preview select previous View") {
                                await session.selectPreviousExperience()
                            }
                        }
                        Button(
                            String(localized: .dashboardNextViewAction),
                            systemSymbol: .forwardFill,
                        ) {
                            Task(name: "Throw preview select next View") {
                                await session.selectNextExperience()
                            }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.black.opacity(0.7))
                    .padding(.horizontal)
                    .safeAreaPadding(.bottom)
                }
            }
            .accessibilityAddTraits(.isModal)
    }
}

#if DEBUG
    extension PreviewProjectionContainer: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Multiple Views",
                configurations: [SnapshotConfiguration(device: .iPhone)],
                settle: .immediate,
            ) {
                PreviewProjectionContainer(
                    session: .experienceDashboardSnapshotFixture(.rotating),
                    outputID: ProjectionOutputID(rawValue: "snapshot-preview"),
                    onExit: {},
                )
                .throwBroadwayRoot()
            }
        }
    }

    #Preview("Multiple Views") {
        PreviewProjectionContainer.snapshotPreviews
    }
#endif
