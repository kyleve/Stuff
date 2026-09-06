import SFSafeSymbols
import SwiftUI

struct LocationStepView: View {
    @Bindable var model: OnboardingFlowModel
    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: .onboardingLocationTitle),
                    selection: $model.locationMode,
                ) {
                    Text(.locationUseGPS).tag(LocationSelectionMode.gps)
                    Text(.locationManual).tag(LocationSelectionMode.manual)
                }
                .pickerStyle(.segmented)

                if model.locationMode == .gps {
                    Button(String(localized: .locationUseGPS), systemSymbol: .locationFill) {
                        Task(name: "Throw locate observer") {
                            await model.locate()
                        }
                    }
                    LocationHealthRow(health: model.locationHealth)
                    if case .offeredBest = model.locationHealth {
                        Button(
                            String(localized: .locationAcceptBest),
                            systemSymbol: .checkmarkCircle,
                        ) {
                            Task(name: "Throw onboarding accept observer") {
                                await model.acceptOfferedLocation()
                            }
                        }
                        Button(String(localized: .commonRetry), systemSymbol: .arrowClockwise) {
                            Task(name: "Throw onboarding retry observer") {
                                await model.locate()
                            }
                        }
                    }
                } else {
                    TextField(
                        String(localized: .locationLatitude),
                        value: $model.latitude,
                        format: .number.precision(.fractionLength(0 ... 6)),
                    )
                    .keyboardType(.decimalPad)
                    TextField(
                        String(localized: .locationLongitude),
                        value: $model.longitude,
                        format: .number.precision(.fractionLength(0 ... 6)),
                    )
                    .keyboardType(.decimalPad)
                }

                TextField(
                    String(localized: .locationAltitude),
                    value: $model.observerAltitudeFeet,
                    format: .number.precision(.fractionLength(0)),
                )
                .keyboardType(.numbersAndPunctuation)
            } header: {
                Text(.onboardingLocationTitle)
            } footer: {
                Text(.onboardingLocationDescription)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
