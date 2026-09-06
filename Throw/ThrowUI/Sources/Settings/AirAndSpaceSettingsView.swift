import SFSafeSymbols
import SnapshotKit
import SwiftUI
import ThrowCore

struct AirAndSpaceSettingsView: View {
    let session: ThrowSession

    var body: some View {
        List {
            Section {
                NavigationLink(value: ThrowSettingsDestination.airAndSpaceProjection) {
                    Label(String(localized: .settingsMode), systemSymbol: .viewfinderCircle)
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
                NavigationLink(value: ThrowSettingsDestination.airAndSpaceLayers) {
                    Label(String(localized: .settingsLayers), systemSymbol: .square3Layers3d)
                }
                NavigationLink(value: ThrowSettingsDestination.labels) {
                    Label(String(localized: .settingsLabels), systemSymbol: .textformat)
                }
                NavigationLink(value: ThrowSettingsDestination.airAndSpaceAppearance) {
                    Label(
                        String(localized: .settingsAirAndSpaceAppearance),
                        systemSymbol: .paintbrushFill,
                    )
                }
            } footer: {
                Text(.experienceAirAndSpaceDescription)
            }
        }
        .navigationTitle(ProjectionExperiencePresentation(id: .airAndSpace).name)
    }
}

struct AirAndSpaceProjectionSettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Form {
            Section {
                ProjectionModeControl(session: session)
            }
        }
        .navigationTitle(Text(.settingsMode))
    }
}

struct AirAndSpaceLayersSettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Form {
            Section {
                LayerCatalogRows(session: session, experienceID: .airAndSpace)
            }
        }
        .navigationTitle(Text(.settingsLayers))
    }
}

#if DEBUG
    extension AirAndSpaceSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Configured",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    AirAndSpaceSettingsView(session: .fixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        AirAndSpaceSettingsView.snapshotPreviews
    }

    #Preview("Projection") {
        NavigationStack {
            AirAndSpaceProjectionSettingsView(session: .fixture())
        }
        .throwBroadwayRoot()
    }

    #Preview("Layers") {
        NavigationStack {
            AirAndSpaceLayersSettingsView(session: .fixture())
        }
        .throwBroadwayRoot()
    }
#endif
