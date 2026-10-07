import SnapshotKit
import SwiftUI
import WhereCore

/// A transition-specific review; dismissing or waiting never authorizes the data change.
struct DataCompatibilityActivationView: View {
    @Environment(\.stylesheet) private var stylesheet
    let state: DataFeatureAvailabilityModel.State
    let updates: AppUpdateAvailability
    let retry: () async -> Void
    let wait: () -> Void
    let continueWith: (DataCompatibilityActivationApproval) -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: .compatibilityWait), action: wait)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
            case let .available(review), let .needsDeviceReview(review):
                reviewContent(review)
            case .checking:
                DataCompatibilityView(
                    state: .checking,
                    scope: .featureActivation,
                    updates: updates,
                    retry: retry,
                )
            case let .updateRequired(status):
                DataCompatibilityView(
                    state: .updateRequired(status),
                    scope: .featureActivation,
                    updates: updates,
                    retry: retry,
                )
            case let .verificationFailed(description):
                DataCompatibilityView(
                    state: .verificationFailed(description: description),
                    scope: .featureActivation,
                    updates: updates,
                    retry: retry,
                )
        }
    }

    private func reviewContent(_ review: DataCompatibilityActivationReview) -> some View {
        Form {
            Section {
                Text(review.requiresConfirmation
                    ? String(localized: .compatibilityActivationMessage)
                    : String(localized: .compatibilityReadyMessage))
                LabeledContent(String(localized: .compatibilityRequiredVersion)) {
                    Text(review.requiredVersion.rawValue, format: .number)
                }
            }
            if review.requiresConfirmation {
                Section(String(localized: .compatibilityAffectedDevices)) {
                    ForEach(review.affectedDevices) { device in
                        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                            Text(device.displayName).font(.headline)
                            Text(device.supportedVersion == nil
                                ? String(localized: .compatibilityUnknownDevice)
                                : String(localized: .compatibilityOutdatedDevice))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button(String(localized: .compatibilityWait), action: wait)
                        .keyboardShortcut(.defaultAction)
                    Button(
                        String(localized: .compatibilityContinueAnyway),
                        role: .destructive,
                        action: { continueWith(.continueAnyway(review)) },
                    )
                } footer: {
                    Text(String(localized: .compatibilityRetiredDevices))
                }
            } else {
                Section {
                    Button(String(localized: .onboardingContinue)) {
                        continueWith(.readyDevicesOnly)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .navigationTitle(review.requiresConfirmation
            ? String(localized: .compatibilityActivationTitle)
            : String(localized: .compatibilityReadyTitle))
    }
}

#if DEBUG
    extension DataCompatibilityActivationView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "UnreadyDevices", configurations: .fullContentScreenDefaults) {
                Self(
                    state: .needsDeviceReview(.preview),
                    updates: .noBuildsPublished,
                    retry: {},
                    wait: {},
                    continueWith: { _ in },
                )
            }
            whereSnapshot(name: "Ready", configurations: .fullContentScreenDefaults) {
                Self(
                    state: .available(.init(
                        requiredVersion: DataCompatibilityVersion(rawValue: 2),
                        previousVersion: .initial,
                        generationID: .initial,
                        affectedDevices: [],
                    )),
                    updates: .noBuildsPublished,
                    retry: {},
                    wait: {},
                    continueWith: { _ in },
                )
            }
            whereSnapshot(name: "Checking", configurations: .fullContentPhoneLightDark) {
                Self(
                    state: .checking,
                    updates: .noBuildsPublished,
                    retry: {},
                    wait: {},
                    continueWith: { _ in },
                )
            }
            whereSnapshot(name: "UpdateRequired", configurations: .fullContentPhoneLightDark) {
                Self(
                    state: .updateRequired(.init(
                        supportedVersion: .initial,
                        requiredVersion: DataCompatibilityVersion(rawValue: 2),
                    )),
                    updates: .noBuildsPublished,
                    retry: {},
                    wait: {},
                    continueWith: { _ in },
                )
            }
            whereSnapshot(name: "VerificationFailed", configurations: .fullContentPhoneLightDark) {
                Self(
                    state: .verificationFailed(description: "Could not read device readiness."),
                    updates: .noBuildsPublished,
                    retry: {},
                    wait: {},
                    continueWith: { _ in },
                )
            }
        }
    }

    extension DataCompatibilityActivationReview {
        static var preview: Self {
            .init(
                requiredVersion: DataCompatibilityVersion(rawValue: 2),
                previousVersion: .initial,
                generationID: .initial,
                affectedDevices: [
                    .init(
                        id: RecordingDeviceID(rawValue: UUID()),
                        displayName: "My iPhone",
                        supportedVersion: .initial,
                    ),
                    .init(
                        id: RecordingDeviceID(rawValue: UUID()),
                        displayName: "My iPad",
                        supportedVersion: nil,
                    ),
                ],
            )
        }
    }

    extension DataCompatibilityActivationView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            Self.self,
            title: "Coordinate Device Updates",
            navigationContainer: .none,
        )
    }

    #Preview { DataCompatibilityActivationView.snapshotPreviews }
#endif
