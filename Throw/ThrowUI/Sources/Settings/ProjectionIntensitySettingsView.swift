import SnapshotKit
import SwiftUI

struct ProjectionIntensitySettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: .settingsIntensity)) {
                    Text(session.intensityPercent / 100, format: .percent)
                }
                Slider(value: $session.intensityPercent, in: 20 ... 100, step: 5)
                    .accessibilityLabel(Text(.settingsIntensity))
                    .accessibilityValue(
                        Text(session.intensityPercent / 100, format: .percent),
                    )
            } footer: {
                Text(.settingsProjectionIntensityDescription)
            }
        }
        .navigationTitle(Text(.settingsProjectionIntensity))
    }
}

#if DEBUG
    extension ProjectionIntensitySettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Default",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    ProjectionIntensitySettingsView(session: .fixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        ProjectionIntensitySettingsView.snapshotPreviews
    }
#endif
