import SFSafeSymbols
import SwiftUI

struct QuietHoursSettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Form {
            if let settingsFailure = session.settingsFailure {
                Section {
                    SettingsFailureMessage(detail: settingsFailure)
                }
            }
            Toggle(String(localized: .quietEnable), isOn: $session.quietHoursEnabled)
            if session.quietHoursEnabled {
                DatePicker(
                    String(localized: .quietStart),
                    selection: $session.quietStart,
                    displayedComponents: .hourAndMinute,
                )
                DatePicker(
                    String(localized: .quietEnd),
                    selection: $session.quietEnd,
                    displayedComponents: .hourAndMinute,
                )
                if session.quietScheduleIsValid == false {
                    Label(
                        String(localized: .quietEqualEndpointsError),
                        systemSymbol: .exclamationmarkTriangleFill,
                    )
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(Text(.settingsQuiet))
    }
}
