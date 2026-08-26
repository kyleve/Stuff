import SFSafeSymbols
import SnapshotKit
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
                    Text(.sourceFlightradar24).tag(AircraftSourceChoice.flightradar24)
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
                RapidAPICadenceSection(model: model)
                RapidAPICredentialSection(model: model)
            }

            if model.choice == .flightradar24 {
                Flightradar24CadenceSection(model: model)
                Flightradar24CredentialSection(model: model)
            }

            AircraftSourceApplySection(model: model)
        }
        .navigationTitle(Text(.settingsSource))
        .task(id: model.choice) {
            await model.loadFlightradar24Usage()
        }
        .onDisappear(perform: model.discardTestedDraft)
    }

    private var sourceDescription: LocalizedStringResource {
        switch model.choice {
            case .adsbLol: .sourceAdsbLolDescription
            case .readsb: .sourceReadsbDescription
            case .adsbExchange: .sourceAdsbExchangeDescription
            case .flightradar24: .sourceFlightradar24Description
        }
    }
}

#if DEBUG
    extension AircraftSourceSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "FR24 recent credit usage",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
            ) {
                NavigationStack {
                    AircraftSourceSettingsView(
                        session: .flightradar24SourceSettingsSnapshotFixture(),
                    )
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview("Aircraft source settings") {
        AircraftSourceSettingsView.snapshotPreviews
    }
#endif
