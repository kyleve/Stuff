#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// Developer-only controls for validating crash capture and symbolication.
    struct DeveloperCrashTestingView: View {
        var body: some View {
            List {
                Section {
                    ForEach(DeveloperCrash.allCases) { crash in
                        DeveloperCrashButton(crash: crash)
                    }
                } footer: {
                    Text(String(localized: .developerCrashTestingFooter))
                }
            }
            .navigationTitle(String(localized: .developerCrashTestingTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    extension DeveloperCrashTestingView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    DeveloperCrashTestingView()
                }
            }
        }
    }

    #Preview {
        DeveloperCrashTestingView.snapshotPreviews
    }
#endif
