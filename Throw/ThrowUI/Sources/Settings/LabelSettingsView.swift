import SwiftUI
import ThrowCore

struct LabelSettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Form {
            if let settingsFailure = session.settingsFailure {
                Section {
                    SettingsFailureMessage(detail: settingsFailure)
                }
            }
            Picker(String(localized: .settingsLabels), selection: $session.labelMode) {
                Text(.labelsMarksOnly).tag(FlightLabelMode.marksOnly)
                Text(.labelsCallsigns).tag(FlightLabelMode.callsigns)
                Text(.labelsAdaptive).tag(FlightLabelMode.adaptive)
            }
            Toggle(String(localized: .settingsGroundAircraft), isOn: $session.includeGroundAircraft)
                .disabled(session.projectionMode != .map)
        }
        .navigationTitle(Text(.settingsLabels))
    }
}
