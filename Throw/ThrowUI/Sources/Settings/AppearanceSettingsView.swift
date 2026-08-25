import SnapshotKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Form {
            if let settingsFailure = session.settingsFailure {
                Section {
                    SettingsFailureMessage(detail: settingsFailure)
                }
            }
            Section {
                LabeledContent(String(localized: .settingsMarkSize)) {
                    Text(session.markSizePercent / 100, format: .percent)
                }
                Slider(value: $session.markSizePercent, in: 50 ... 200, step: 5)
                    .accessibilityLabel(Text(.settingsMarkSize))
                    .accessibilityValue(
                        Text(session.markSizePercent / 100, format: .percent),
                    )
                LabeledContent(String(localized: .settingsIntensity)) {
                    Text(session.intensityPercent / 100, format: .percent)
                }
                Slider(value: $session.intensityPercent, in: 20 ... 100, step: 5)
                    .accessibilityLabel(Text(.settingsIntensity))
                    .accessibilityValue(
                        Text(session.intensityPercent / 100, format: .percent),
                    )
            }
            Section {
                LabeledContent(String(localized: .settingsGeographyIntensity)) {
                    Text(session.geographyIntensityPercent / 100, format: .percent)
                }
                Slider(
                    value: $session.geographyIntensityPercent,
                    in: 0 ... 20,
                    step: 1,
                )
                .accessibilityLabel(Text(.settingsGeographyIntensity))
                .accessibilityValue(
                    Text(session.geographyIntensityPercent / 100, format: .percent),
                )
            } header: {
                Text(.layerGeography)
            } footer: {
                Text(.settingsGeographyIntensityDescription)
            }
        }
        .navigationTitle(Text(.settingsAppearance))
    }
}

#if DEBUG
    extension AppearanceSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Geography",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    AppearanceSettingsView(session: .fixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        AppearanceSettingsView.snapshotPreviews
    }
#endif
