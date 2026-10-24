import SnapshotKit
import SwiftUI
import ThrowCore

struct AppearanceSettingsView: View {
    private let session: ThrowSession
    @State private var markSizePercent: Double
    @State private var airlineAccentsEnabled: Bool
    @State private var geographyIntensityPercent: Double

    init(session: ThrowSession) {
        self.session = session
        _markSizePercent = State(initialValue: session.markSizePercent)
        _airlineAccentsEnabled = State(initialValue: session.airlineAccentsEnabled)
        _geographyIntensityPercent = State(initialValue: session.geographyIntensityPercent)
    }

    var body: some View {
        let failures = session.postLaunchFailures(for: .appearance)
        Form {
            if failures.isEmpty == false {
                Section {
                    SettingsFailureMessages(failures: failures)
                }
            }
            Section {
                LabeledContent(String(localized: .settingsMarkSize)) {
                    Text(markSizePercent / 100, format: .percent)
                }
                Slider(value: $markSizePercent, in: 50 ... 200, step: 5)
                    .accessibilityLabel(Text(.settingsMarkSize))
                    .accessibilityValue(
                        Text(markSizePercent / 100, format: .percent),
                    )
            }
            Section {
                Toggle(
                    String(localized: .settingsAirlineAccents),
                    isOn: $airlineAccentsEnabled,
                )
                AircraftFamilyLegend()
            } header: {
                Text(.settingsAircraftAppearance)
            } footer: {
                Text(.settingsAirlineAccentsDescription)
            }
            Section {
                AircraftActivityLegend()
            } header: {
                Text(.settingsFlightActivityCues)
            } footer: {
                Text(.settingsFlightActivityCuesDescription)
            }
            Section {
                LabeledContent(String(localized: .settingsGeographyIntensity)) {
                    Text(geographyIntensityPercent / 100, format: .percent)
                }
                Slider(
                    value: $geographyIntensityPercent,
                    in: 0 ... 20,
                    step: 1,
                )
                .accessibilityLabel(Text(.settingsGeographyIntensity))
                .accessibilityValue(
                    Text(geographyIntensityPercent / 100, format: .percent),
                )
            } header: {
                Text(.layerGeography)
            } footer: {
                Text(.settingsGeographyIntensityDescription)
            }
        }
        .navigationTitle(Text(.settingsAirAndSpaceAppearance))
        .onChange(of: markSizePercent) { _, markSizePercent in
            do {
                let preferences = try session.airAndSpacePreferences
                    .replacingMarkSizePercent(markSizePercent)
                session.updateAirAndSpacePreferences(preferences)
            } catch is ThrowValidationError {
                return
            } catch {
                assertionFailure("Mark-size validation produced an unexpected error: \(error)")
            }
        }
        .onChange(of: airlineAccentsEnabled) { _, airlineAccentsEnabled in
            let preferences = session.airAndSpacePreferences
                .replacingAirlineAccentsEnabled(airlineAccentsEnabled)
            session.updateAirAndSpacePreferences(preferences)
        }
        .onChange(of: geographyIntensityPercent) { _, geographyIntensityPercent in
            do {
                let geography = try session.airAndSpacePreferences.geography
                    .replacingIntensityPercent(geographyIntensityPercent)
                let preferences = session.airAndSpacePreferences
                    .replacingGeography(geography)
                session.updateAirAndSpacePreferences(preferences)
            } catch is ThrowValidationError {
                return
            } catch {
                assertionFailure("Geography validation produced an unexpected error: \(error)")
            }
        }
        .onChange(of: session.markSizePercent) { _, value in
            markSizePercent = value
        }
        .onChange(of: session.airlineAccentsEnabled) { _, value in
            airlineAccentsEnabled = value
        }
        .onChange(of: session.geographyIntensityPercent) { _, value in
            geographyIntensityPercent = value
        }
    }
}

#if DEBUG
    extension AppearanceSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Geography",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    AppearanceSettingsView(session: .fixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        AppearanceSettingsView.snapshotPreviews
    }
#endif
