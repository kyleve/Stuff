import SFSafeSymbols
import SwiftUI

struct ThrowSettingsView: View {
    let session: ThrowSession
    let outputs: ControllerProjectionOutputs

    var body: some View {
        List {
            if let settingsFailure = session.settingsFailure {
                Section {
                    SettingsFailureMessage(detail: settingsFailure)
                }
            }
            NavigationLink(value: ThrowSettingsDestination.location) {
                Label(String(localized: .settingsLocation), systemSymbol: .locationFill)
            }
            NavigationLink(value: ThrowSettingsDestination.mapCenter) {
                Label(String(localized: .settingsMapCenter), systemSymbol: .mapFill)
            }
            NavigationLink(value: ThrowSettingsDestination.source) {
                Label(
                    String(localized: .settingsSource),
                    systemSymbol: .antennaRadiowavesLeftAndRight,
                )
            }
            NavigationLink(value: ThrowSettingsDestination.calibration) {
                Label(String(localized: .calibrationTitle), systemSymbol: .viewfinder)
            }
            NavigationLink(value: ThrowSettingsDestination.appearance) {
                Label(String(localized: .settingsAppearance), systemSymbol: .paintbrushFill)
            }
            NavigationLink(value: ThrowSettingsDestination.labels) {
                Label(String(localized: .settingsLabels), systemSymbol: .textformat)
            }
            NavigationLink(value: ThrowSettingsDestination.quiet) {
                Label(String(localized: .settingsQuiet), systemSymbol: .moonStarsFill)
            }
            NavigationLink(value: ThrowSettingsDestination.about) {
                Label(String(localized: .aboutTitle), systemSymbol: .infoCircle)
            }
        }
        .navigationTitle(Text(.settingsTitle))
        .navigationDestination(for: ThrowSettingsDestination.self) { destination in
            switch destination {
                case .location:
                    LocationSettingsView(session: session)
                case .mapCenter:
                    MapCenterSettingsView(session: session)
                case .source:
                    AircraftSourceSettingsView(session: session)
                case .calibration:
                    CalibrationSettingsView(session: session, outputID: outputs.calibration)
                case .appearance:
                    AppearanceSettingsView(session: session)
                case .labels:
                    LabelSettingsView(session: session)
                case .quiet:
                    QuietHoursSettingsView(session: session)
                case .about:
                    ThrowAboutView(session: session)
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            ThrowSettingsView(session: .fixture(), outputs: ControllerProjectionOutputs())
        }
        .throwBroadwayRoot()
    }
#endif
