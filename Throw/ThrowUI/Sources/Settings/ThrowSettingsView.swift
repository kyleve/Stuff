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
            Section {
                NavigationLink(value: ThrowSettingsDestination.views) {
                    Label(String(localized: .viewsTitle), systemSymbol: .rectangleStack)
                }
            }
            Section(String(localized: .settingsGlobal)) {
                NavigationLink(value: ThrowSettingsDestination.location) {
                    Label(String(localized: .settingsLocation), systemSymbol: .locationFill)
                }
                NavigationLink(value: ThrowSettingsDestination.calibration) {
                    Label(String(localized: .calibrationTitle), systemSymbol: .viewfinder)
                }
                NavigationLink(value: ThrowSettingsDestination.projectionIntensity) {
                    Label(
                        String(localized: .settingsProjectionIntensity),
                        systemSymbol: .sunMaxFill,
                    )
                }
                NavigationLink(value: ThrowSettingsDestination.quiet) {
                    Label(String(localized: .settingsQuiet), systemSymbol: .moonStarsFill)
                }
                NavigationLink(value: ThrowSettingsDestination.about) {
                    Label(String(localized: .aboutTitle), systemSymbol: .infoCircle)
                }
            }
        }
        .navigationTitle(Text(.settingsTitle))
        .navigationDestination(for: ThrowSettingsDestination.self) { destination in
            switch destination {
                case .views:
                    ProjectionViewsSettingsView(session: session)
                case .airAndSpace:
                    AirAndSpaceSettingsView(session: session)
                case .airAndSpaceProjection:
                    AirAndSpaceProjectionSettingsView(session: session)
                case .airAndSpaceLayers:
                    AirAndSpaceLayersSettingsView(session: session)
                case .airAndSpaceAppearance:
                    AppearanceSettingsView(session: session)
                case .location:
                    LocationSettingsView(session: session)
                case .mapCenter:
                    MapCenterSettingsView(session: session)
                case .source:
                    AircraftSourceSettingsView(session: session)
                case .calibration:
                    CalibrationSettingsView(session: session, outputID: outputs.calibration)
                case .projectionIntensity:
                    ProjectionIntensitySettingsView(session: session)
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
