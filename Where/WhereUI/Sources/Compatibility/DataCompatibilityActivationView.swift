import SnapshotKit
import SwiftUI
import WhereCore

/// A transition-specific review; dismissing or waiting never authorizes the data change.
struct DataCompatibilityActivationView: View {
    @Environment(\.stylesheet) private var stylesheet
    let review: DataCompatibilityActivationReview
    let wait: () -> Void
    let continueAnyway: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: .compatibilityActivationMessage))
                    LabeledContent(String(localized: .compatibilityRequiredVersion)) {
                        Text(review.requiredVersion.rawValue, format: .number)
                    }
                }
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
                        action: continueAnyway,
                    )
                } footer: {
                    Text(String(localized: .compatibilityRetiredDevices))
                }
            }
            .navigationTitle(String(localized: .compatibilityActivationTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .compatibilityWait), action: wait)
                }
            }
        }
    }
}

#if DEBUG
    extension DataCompatibilityActivationView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "UnreadyDevices", configurations: .fullContentScreenDefaults) {
                Self(review: .preview, wait: {}, continueAnyway: {})
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
