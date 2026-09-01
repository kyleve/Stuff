import SwiftUI
import ThrowCore

struct LabelSettingsView: View {
    private let session: ThrowSession
    @State private var labelMode: FlightLabelMode
    @State private var includeGroundAircraft: Bool

    init(session: ThrowSession) {
        self.session = session
        _labelMode = State(initialValue: session.labelMode)
        _includeGroundAircraft = State(initialValue: session.includeGroundAircraft)
    }

    var body: some View {
        Form {
            if let settingsFailure = session.settingsFailure {
                Section {
                    SettingsFailureMessage(detail: settingsFailure)
                }
            }
            Picker(String(localized: .settingsLabels), selection: $labelMode) {
                Text(.labelsMarksOnly).tag(FlightLabelMode.marksOnly)
                Text(.labelsCallsigns).tag(FlightLabelMode.callsigns)
                Text(.labelsAdaptive).tag(FlightLabelMode.adaptive)
            }
            Toggle(String(localized: .settingsGroundAircraft), isOn: $includeGroundAircraft)
                .disabled(session.projectionMode != .map)
        }
        .navigationTitle(Text(.settingsLabels))
        .onChange(of: labelMode) { _, labelMode in
            let preferences = session.airAndSpacePreferences.replacingLabelMode(labelMode)
            session.updateAirAndSpacePreferences(preferences)
        }
        .onChange(of: includeGroundAircraft) { _, includeGroundAircraft in
            let preferences = session.airAndSpacePreferences
                .replacingIncludeGroundAircraft(includeGroundAircraft)
            session.updateAirAndSpacePreferences(preferences)
        }
        .onChange(of: session.labelMode) { _, value in
            labelMode = value
        }
        .onChange(of: session.includeGroundAircraft) { _, value in
            includeGroundAircraft = value
        }
    }
}
