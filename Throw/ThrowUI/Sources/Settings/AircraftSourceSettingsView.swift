import SFSafeSymbols
import SwiftUI

struct AircraftSourceSettingsView: View {
    @State private var model: AircraftSourceSettingsModel

    init(session: ThrowSession) {
        _model = State(initialValue: AircraftSourceSettingsModel(session: session))
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
                Picker(String(localized: .settingsSource), selection: $model.choice) {
                    Text(.sourceAdsbLol).tag(AircraftSourceChoice.adsbLol)
                    Text(.sourceReadsb).tag(AircraftSourceChoice.readsb)
                    Text(.sourceAdsbExchange).tag(AircraftSourceChoice.adsbExchange)
                }
                Text(sourceDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if model.choice == .readsb {
                Section {
                    TextField(String(localized: .sourceLocalURL), text: $model.readsbURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
            }

            if model.choice == .adsbExchange {
                RapidAPICredentialSection(model: model)
                RapidAPICadenceSection(model: model)
            }

            Section {
                Button(
                    String(localized: .sourceTestConnection),
                    systemSymbol: .antennaRadiowavesLeftAndRight,
                ) {
                    Task(name: "Throw settings test source") { await model.test() }
                }
                .disabled(model.validation == .testing)
                SourceValidationLabel(state: model.validation)

                Button(String(localized: .sourceUseSource), systemSymbol: .checkmarkCircle) {
                    Task(name: "Throw switch source") { await model.useSource() }
                }
                .disabled(model.canUseSource == false)
            }
        }
        .navigationTitle(Text(.settingsSource))
        .onDisappear(perform: model.discardTestedDraft)
    }

    private var sourceDescription: LocalizedStringResource {
        switch model.choice {
            case .adsbLol: .sourceAdsbLolDescription
            case .readsb: .sourceReadsbDescription
            case .adsbExchange: .sourceAdsbExchangeDescription
        }
    }
}
