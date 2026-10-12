import SnapshotKit
import SwiftUI
@_spi(Testing) import WhereCore

/// The blocked app surface; it exposes no domain data or compatibility override.
struct DataCompatibilityView: View {
    let state: DataCompatibilityState
    let updates: AppUpdateAvailability
    let retry: () -> Void
    let manageRecording: () -> Void
    @MotionIsStatic private var motionIsStatic

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch state {
                        case .checking, .compatible:
                            if motionIsStatic {
                                Text(String(localized: .compatibilityChecking))
                            } else {
                                ProgressView(String(localized: .compatibilityChecking))
                            }
                        case .recordingChoiceRequired:
                            Text(String(localized: .compatibilityChooseRecording))
                        case .waitingForRecordingDevice:
                            Text(String(localized: .compatibilityUpdateRecorder))
                        case .updateRequired:
                            Text(String(localized: .compatibilityUpdateThisDevice))
                        case .verificationFailed:
                            Text(String(localized: .compatibilityVerificationFailed))
                    }
                }
                if case .updateRequired = state { updateLinks }
                switch state {
                    case .recordingChoiceRequired, .waitingForRecordingDevice, .verificationFailed:
                        Section { Button(
                            String(localized: .compatibilityManageRecording),
                            action: manageRecording,
                        ) }
                    case .checking, .compatible, .updateRequired: EmptyView()
                }
                if case .checking = state {} else {
                    Section { Button(String(localized: .commonRetry), action: retry) }
                }
                Section(String(localized: .compatibilityDiagnostics)) {
                    Text(String(localized: .compatibilityBuildVersion(DataCompatibilityVersion
                            .current.rawValue)))
                    if case let .updateRequired(version) = state {
                        Text(String(localized: .compatibilityRequiredVersion(version.rawValue)))
                    }
                    if case let .verificationFailed(message) = state {
                        Text(message).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(String(localized: .compatibilityTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var updateLinks: some View {
        Section {
            switch updates {
                case .noBuildsPublished: Text(String(localized: .compatibilityNoBuilds))
                case let .published(links):
                    switch links {
                        case let .testFlight(url): Link(
                                String(localized: .compatibilityTestFlight),
                                destination: url,
                            )
                        case let .appStore(url): Link(
                                String(localized: .compatibilityAppStore),
                                destination: url,
                            )
                        case let .both(testFlight, appStore):
                            Link(
                                String(localized: .compatibilityTestFlight),
                                destination: testFlight,
                            )
                            Link(String(localized: .compatibilityAppStore), destination: appStore)
                    }
            }
        }
    }
}

#if DEBUG
    extension DataCompatibilityView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let owner = RecordingAuthority.ownedForTesting(by: .init(rawValue: UUID())).owner!
            struct Example {
                let name: String
                let state: DataCompatibilityState
                let updates: AppUpdateAvailability
            }
            let examples: [Example] = [
                .init(name: "Checking", state: .checking, updates: .noBuildsPublished),
                .init(
                    name: "ChooseRecording",
                    state: .recordingChoiceRequired,
                    updates: .noBuildsPublished,
                ),
                .init(
                    name: "Update",
                    state: .updateRequired(.init(rawValue: 2)),
                    updates: .noBuildsPublished,
                ),
                .init(
                    name: "Waiting",
                    state: .waitingForRecordingDevice(owner),
                    updates: .noBuildsPublished,
                ),
                .init(
                    name: "VerificationFailed",
                    state: .verificationFailed("The shared requirement could not be verified."),
                    updates: .noBuildsPublished,
                ),
                .init(
                    name: "Published",
                    state: .updateRequired(.init(rawValue: 2)),
                    updates: .published(.both(
                        testFlight: URL(string: "https://testflight.apple.com")!,
                        appStore: URL(string: "https://apps.apple.com")!,
                    )),
                ),
            ]
            return examples.map { example in
                whereSnapshot(name: example.name, configurations: .fullContentScreenDefaults) {
                    DataCompatibilityView(
                        state: example.state,
                        updates: example.updates,
                        retry: {},
                        manageRecording: {},
                    )
                }
            }
        }
    }

    #Preview { DataCompatibilityView(
        state: .updateRequired(.init(rawValue: 2)),
        updates: .noBuildsPublished,
        retry: {},
        manageRecording: {},
    ).whereBroadwayRoot() }

    extension DataCompatibilityView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            DataCompatibilityView.self,
            title: "App compatibility",
            navigationContainer: .none,
        ) { _ in
            DataCompatibilityView(
                state: .updateRequired(.init(rawValue: 2)),
                updates: .noBuildsPublished,
                retry: {},
                manageRecording: {},
            )
        }
    }
#endif
