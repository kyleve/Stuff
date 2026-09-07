import SwiftUI

#if DEBUG
    import SnapshotKit
#endif

struct SettingsFailureMessages: View {
    let failures: [ThrowPostLaunchFailure]

    var body: some View {
        ForEach(failures) { failure in
            SettingsFailureMessage(failure: failure)
        }
    }
}

#if DEBUG
    extension SettingsFailureMessages: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Multiple Owners",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    Form {
                        Section {
                            SettingsFailureMessages(failures: [
                                .preferencePersistence,
                                .aircraftSource,
                                .location(.persistence),
                            ])
                        }
                    }
                    .navigationTitle(Text(.settingsTitle))
                }
                .throwBroadwayRoot()
            }
        }

        #Preview("Post-launch failures") {
            SettingsFailureMessages.snapshotPreviews
        }
    }
#endif
