import SFSafeSymbols
import SwiftUI
import ThrowCore

struct LocationSettingsView: View {
    @State private var model: LocationSettingsModel

    init(session: ThrowSession) {
        _model = State(initialValue: LocationSettingsModel(session: session))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if let settingsFailure = model.settingsFailure {
                Section {
                    SettingsFailureMessage(detail: settingsFailure)
                }
            }
            Section {
                Picker(String(localized: .settingsLocation), selection: $model.mode) {
                    Text(.locationUseGPS).tag(ObserverLocationMode.gps)
                    Text(.locationManual).tag(ObserverLocationMode.manual)
                }
                .pickerStyle(.segmented)

                LocationHealthRow(health: model.health)
                if model.mode == .gps {
                    Button(
                        String(localized: .dashboardRefreshLocation),
                        systemSymbol: .locationFill,
                    ) {
                        Task(name: "Throw settings refresh observer") { await model.refresh() }
                    }
                    if case .offeredBest = model.health {
                        Button(
                            String(localized: .locationAcceptBest),
                            systemSymbol: .checkmarkCircle,
                        ) {
                            Task(name: "Throw settings accept observer") { await model.acceptBest()
                            }
                        }
                        Button(String(localized: .commonRetry), systemSymbol: .arrowClockwise) {
                            Task(name: "Throw settings retry observer") { await model.refresh() }
                        }
                    }
                }
            }

            Section {
                TextField(
                    String(localized: .locationLatitude),
                    value: $model.latitude,
                    format: .number.precision(.fractionLength(0 ... 6)),
                )
                .keyboardType(.numbersAndPunctuation)
                .disabled(model.mode == .gps)
                TextField(
                    String(localized: .locationLongitude),
                    value: $model.longitude,
                    format: .number.precision(.fractionLength(0 ... 6)),
                )
                .keyboardType(.numbersAndPunctuation)
                .disabled(model.mode == .gps)
                TextField(
                    String(localized: .locationAltitude),
                    value: $model.altitudeFeet,
                    format: .number.precision(.fractionLength(0)),
                )
                .keyboardType(.numbersAndPunctuation)
                Button(String(localized: .commonSave), systemSymbol: .checkmarkCircle) {
                    Task(name: "Throw save observer") { await model.save() }
                }
                .disabled(model.isSaving)
            } footer: {
                Text(.onboardingLocationDescription)
            }
        }
        .navigationTitle(Text(.settingsLocation))
    }
}
