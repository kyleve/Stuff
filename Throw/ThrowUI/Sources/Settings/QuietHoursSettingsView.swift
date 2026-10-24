import SFSafeSymbols
import SwiftUI

struct QuietHoursSettingsView: View {
    @State private var model: QuietHoursSettingsModel

    init(session: ThrowSession) {
        _model = State(initialValue: QuietHoursSettingsModel(session: session))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if model.postLaunchFailures.isEmpty == false {
                Section {
                    SettingsFailureMessages(failures: model.postLaunchFailures)
                }
            }
            Toggle(String(localized: .quietEnable), isOn: $model.isEnabled)
            if model.isEnabled {
                DatePicker(
                    String(localized: .quietStart),
                    selection: $model.start,
                    displayedComponents: .hourAndMinute,
                )
                DatePicker(
                    String(localized: .quietEnd),
                    selection: $model.end,
                    displayedComponents: .hourAndMinute,
                )
                if model.scheduleIsValid == false {
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
