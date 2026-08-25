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
        }
        .navigationTitle(Text(.settingsAppearance))
    }
}
