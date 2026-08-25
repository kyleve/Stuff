import SFSafeSymbols
import SwiftUI

struct AppearanceStepView: View {
    @Bindable var model: OnboardingFlowModel

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    String(localized: .settingsLabels),
                    value: String(localized: .labelsAdaptive),
                )
                LabeledContent(
                    String(localized: .settingsLayers),
                    value: String(localized: .layerFlights),
                )
                LabeledContent(
                    String(localized: .settingsGroundAircraft),
                    value: String(localized: .commonOff),
                )
                Toggle(String(localized: .quietEnable), isOn: $model.quietEnabled)
                if model.quietEnabled {
                    DatePicker(
                        String(localized: .quietStart),
                        selection: $model.quietStart,
                        displayedComponents: .hourAndMinute,
                    )
                    DatePicker(
                        String(localized: .quietEnd),
                        selection: $model.quietEnd,
                        displayedComponents: .hourAndMinute,
                    )
                    if model.quietScheduleIsValid == false {
                        Label(
                            String(localized: .quietEqualEndpointsError),
                            systemSymbol: .exclamationmarkTriangleFill,
                        )
                        .foregroundStyle(.red)
                    }
                }
            } header: {
                Text(.onboardingAppearanceTitle)
            } footer: {
                Text(.onboardingAppearanceDescription)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
