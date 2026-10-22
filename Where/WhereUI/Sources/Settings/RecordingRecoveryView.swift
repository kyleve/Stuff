import SnapshotKit
import SwiftUI
import WhereCore

/// Explicit forced replacement and the treatment of possible offline overlap.
struct RecordingRecoveryView: View {
    let deviceName: String
    let confirm: (RecordingRecoveryHistory) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: .recordingRecoveryExplanation(deviceName)))
                    Text(String(localized: .recordingRecoveryOfflineWarning))
                }
                Section {
                    Button(String(localized: .recordingRecoveryKeep)) { confirm(.keep) }
                    Button(String(localized: .recordingRecoveryExclude)) {
                        confirm(.excludeAfterReplacement)
                    }
                } footer: {
                    Text(String(localized: .recordingRecoveryRawHistory))
                }
            }
            .navigationTitle(String(localized: .recordingRecoveryTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
    extension RecordingRecoveryView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Recovery", configurations: .fullContentScreenDefaults) {
                RecordingRecoveryView(deviceName: "Previous iPhone", confirm: { _ in })
            }
        }
    }

    #Preview {
        RecordingRecoveryView(deviceName: "Previous iPhone", confirm: { _ in }).whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension RecordingRecoveryView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            RecordingRecoveryView.self,
            title: "Replace recording device",
            navigationContainer: .none,
        ) { _ in
            RecordingRecoveryView(deviceName: "Previous iPhone", confirm: { _ in })
        }
    }
#endif
