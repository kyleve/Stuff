import PortholeRuntime
import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

/// Renders the latest sampled value through the same inspectable evidence controls as a call.
struct PortholeObservationView: View {
    let state: PortholeObservationModel.State

    var body: some View {
        Group {
            status
            if let session = state.session {
                if let sample = session.sample {
                    LabeledContent("Sample", value: sample.sequence.formatted())
                    LabeledContent(
                        "Captured",
                        value: sample.capturedAt.formatted(date: .abbreviated, time: .standard),
                    )
                    PortholeValueView(value: sample.value)
                    if session.skippedSamples {
                        Label(
                            "Some intermediate samples were skipped.",
                            systemSymbol: .exclamationmarkTriangle,
                        )
                    }
                    Text("This is the latest sample. Earlier values are not recorded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Watched arguments") {
                    PortholeValueView(value: session.request.invocation.arguments)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch state {
            case .idle: Text("No watch has started.").foregroundStyle(.secondary)
            case .starting: ProgressView("Starting watch…")
            case .watching: Label("Watching every second", systemSymbol: .eye)
            case .stopping: ProgressView("Stopping watch…")
            case .stopped: Text("Watch stopped. The last sample remains available.")
            case let .failed(_, message), let .stopFailed(_, message):
                Label(message, systemSymbol: .exclamationmarkTriangle)
        }
    }
}

#if canImport(UIKit)
    extension PortholeObservationView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(name: "Watching", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    Form { Section("Watch") { Self(state: .watching(snapshotSession)) } }
                        .navigationTitle("Detector inputs")
                        .portholeInlineNavigationTitle()
                }.portholeBroadwayRoot()
            }
            SnapshotCase(name: "Stopped", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    Form { Section("Watch") { Self(state: .stopped(snapshotSession)) } }
                        .navigationTitle("Detector inputs")
                        .portholeInlineNavigationTitle()
                }.portholeBroadwayRoot()
            }
            SnapshotCase(name: "StopFailure", configurations: .fullContentScreenDefaults) {
                NavigationStack {
                    Form {
                        Section("Watch") {
                            Self(state: .stopFailed(
                                snapshotSession,
                                "Stop could not be confirmed: the paired device is offline.",
                            ))
                        }
                    }.navigationTitle("Detector inputs")
                        .portholeInlineNavigationTitle()
                }.portholeBroadwayRoot()
            }
        }

        private static var snapshotSession: PortholeObservationModel.Session {
            let scope = PortholeScopeToken(id: .init(rawValue: "example"), generation: UUID())
            let observationID = PortholeObservationID(rawValue: UUID())
            return PortholeObservationModel.Session(
                request: .init(
                    id: observationID,
                    invocation: .init(
                        id: UUID(),
                        scope: scope,
                        capabilityID: .init(rawValue: "example.detector.inputs"),
                        receiver: nil,
                        arguments: .object(["day": .string("2026-09-13")]),
                    ),
                    intervalMilliseconds: 1000,
                ),
                reference: .init(id: observationID, scope: scope),
                sample: .init(
                    sequence: 4,
                    invocationID: UUID(),
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    value: .object(["sampleCount": .integer(18), "candidateFlight": .bool(false)]),
                ),
                skippedSamples: true,
            )
        }
    }

    #if DEBUG
        #Preview { PortholeObservationView.snapshotPreviews }
    #endif
#endif
