import SFSafeSymbols
import SnapshotKit
import SwiftUI
import ThrowCore

struct TransitSettingsView: View {
    private let session: ThrowSession
    @State private var isConfiguring = false
    @State private var mapRadius: Double
    @State private var mapCenterEastOffset: Double
    @State private var mapCenterNorthOffset: Double
    @State private var labelMode: TransitLabelMode
    @State private var geographyEnabled: Bool
    @State private var networkIntensityPercent: Double
    @State private var markSizePercent: Double

    init(session: ThrowSession) {
        self.session = session
        _mapRadius = State(initialValue: session.transitMapRadius)
        _mapCenterEastOffset = State(initialValue: session.transitMapCenterEastOffset.rounded())
        _mapCenterNorthOffset = State(initialValue: session.transitMapCenterNorthOffset.rounded())
        _labelMode = State(initialValue: session.transitLabelMode)
        _geographyEnabled = State(initialValue: session.transitGeographyEnabled)
        _networkIntensityPercent = State(initialValue: session.transitNetworkIntensityPercent)
        _markSizePercent = State(initialValue: session.transitMarkSizePercent)
    }

    var body: some View {
        let failures = session.postLaunchFailures(for: .settings)
        Form {
            if failures.isEmpty == false {
                Section {
                    SettingsFailureMessages(failures: failures)
                }
            }
            if session.transitConfiguration.cityID == nil {
                setupContent
            } else {
                configuredContent
            }
        }
        .navigationTitle(Text(
            String(localized: "transit.title", defaultValue: "NYC Subway"),
        ))
        .onChange(of: mapRadius) { _, mapRadius in
            publishMapRadius(mapRadius)
        }
        .onChange(of: mapCenterEastOffset) { _, eastOffset in
            session.updateTransitMapCenterOffset(
                east: eastOffset,
                north: session.transitMapCenterNorthOffset,
            )
        }
        .onChange(of: mapCenterNorthOffset) { _, northOffset in
            session.updateTransitMapCenterOffset(
                east: session.transitMapCenterEastOffset,
                north: northOffset,
            )
        }
        .onChange(of: labelMode) { _, labelMode in
            let preferences = session.transitPreferences.replacingLabelMode(labelMode)
            session.updateTransitPreferences(preferences)
        }
        .onChange(of: geographyEnabled) { _, geographyEnabled in
            let geography = session.transitPreferences.geography
                .replacingIsEnabled(geographyEnabled)
            let preferences = session.transitPreferences.replacingGeography(geography)
            session.updateTransitPreferences(preferences)
        }
        .onChange(of: networkIntensityPercent) { _, networkIntensityPercent in
            publishNetworkIntensity(networkIntensityPercent)
        }
        .onChange(of: markSizePercent) { _, markSizePercent in
            publishMarkSize(markSizePercent)
        }
        .onChange(of: session.transitMapRadius) { _, value in
            mapRadius = value
        }
        .onChange(of: session.transitMapCenterEastOffset) { _, value in
            mapCenterEastOffset = value.rounded()
        }
        .onChange(of: session.transitMapCenterNorthOffset) { _, value in
            mapCenterNorthOffset = value.rounded()
        }
        .onChange(of: session.transitLabelMode) { _, value in
            labelMode = value
        }
        .onChange(of: session.transitGeographyEnabled) { _, value in
            geographyEnabled = value
        }
        .onChange(of: session.transitNetworkIntensityPercent) { _, value in
            networkIntensityPercent = value
        }
        .onChange(of: session.transitMarkSizePercent) { _, value in
            markSizePercent = value
        }
    }

    private var setupContent: some View {
        Section {
            Label {
                Text(String(
                    localized: "transit.setup.description",
                    defaultValue: "Show moving MTA subway trains over a dim map of the full network.",
                ))
            } icon: {
                Image(systemSymbol: .tramFill)
            }
            Button {
                isConfiguring = true
                Task {
                    defer { isConfiguring = false }
                    _ = await session.configureNewYorkTransit()
                }
            } label: {
                if isConfiguring {
                    ProgressView()
                } else {
                    Text(String(
                        localized: "transit.setup.action",
                        defaultValue: "Download and Test MTA Data",
                    ))
                }
            }
            .disabled(isConfiguring)
        } footer: {
            Text(String(
                localized: "transit.setup.footer",
                defaultValue: "Throw downloads the official MTA supplemented schedule, then tests a live GTFS Realtime feed. The first setup can take a moment.",
            ))
        }
    }

    @ViewBuilder private var configuredContent: some View {
        Section {
            let radiusTitle = String(localized: "transit.map.radius", defaultValue: "Radius")
            LabeledContent(radiusTitle) {
                distanceText(mapRadius)
            }
            Slider(value: $mapRadius, in: TransitMapViewport.allowedRadius, step: 5)
                .accessibilityLabel(radiusTitle)
                .accessibilityValue(accessibleDistanceText(mapRadius))
            offsetSlider(
                title: String(localized: "transit.map.eastWest", defaultValue: "East / West"),
                value: $mapCenterEastOffset,
            )
            offsetSlider(
                title: String(localized: "transit.map.northSouth", defaultValue: "North / South"),
                value: $mapCenterNorthOffset,
            )
        } header: {
            Text(String(localized: "transit.map.section", defaultValue: "Map"))
        } footer: {
            Text(String(
                localized: "transit.map.footer",
                defaultValue: "This center belongs to the NYC view. It does not change your observer location.",
            ))
        }

        Section(String(localized: "transit.labels.section", defaultValue: "Train Labels")) {
            Picker(
                String(localized: "transit.labels.mode", defaultValue: "Labels"),
                selection: $labelMode,
            ) {
                Text(String(localized: "transit.labels.route", defaultValue: "Route Only"))
                    .tag(TransitLabelMode.routeOnly)
                Text(String(localized: "transit.labels.destination", defaultValue: "Destination"))
                    .tag(TransitLabelMode.destination)
                Text(String(localized: "transit.labels.nextStop", defaultValue: "Next Stop"))
                    .tag(TransitLabelMode.nextStop)
            }
        }

        Section {
            Toggle(
                String(localized: "transit.geography", defaultValue: "Geography"),
                isOn: $geographyEnabled,
            )
            percentageSlider(
                title: String(localized: "transit.network.intensity", defaultValue: "Network"),
                value: $networkIntensityPercent,
            )
            percentageSlider(
                title: String(localized: "transit.mark.size", defaultValue: "Train Size"),
                value: $markSizePercent,
                range: 50 ... 200,
            )
        } header: {
            Text(String(localized: "transit.appearance.section", defaultValue: "Appearance"))
        } footer: {
            Text(String(
                localized: "transit.polling.footer",
                defaultValue: "Live MTA feeds update every 30 seconds. Estimated positions move between updates.",
            ))
        }

        Section {
            Button(role: .destructive) {
                Task { await session.removeTransit() }
            } label: {
                Text(String(localized: "transit.remove", defaultValue: "Remove NYC Subway View"))
            }
        }
    }

    private func offsetSlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title) {
                distanceText(value.wrappedValue)
            }
            Slider(value: value, in: -50 ... 50, step: 1)
                .accessibilityLabel(title)
                .accessibilityValue(accessibleDistanceText(value.wrappedValue))
        }
    }

    private func percentageSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 20 ... 100,
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title) {
                Text(value.wrappedValue / 100, format: .percent)
            }
            Slider(value: value, in: range, step: 5)
                .accessibilityLabel(title)
                .accessibilityValue(Text(value.wrappedValue / 100, format: .percent))
        }
    }

    private func distanceText(_ nauticalMiles: Double) -> Text {
        Text(
            Measurement(value: nauticalMiles, unit: UnitLength.nauticalMiles),
            format: .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0)),
            ),
        )
        .monospacedDigit()
    }

    private func accessibleDistanceText(_ nauticalMiles: Double) -> Text {
        Text(
            Measurement(value: nauticalMiles, unit: UnitLength.nauticalMiles),
            format: .measurement(width: .wide, usage: .asProvided),
        )
    }

    private func publishMapRadius(_ mapRadius: Double) {
        do {
            let viewport = try TransitMapViewport(radius: NauticalMiles(value: mapRadius))
            let preferences = session.transitPreferences.replacingMapViewport(viewport)
            session.updateTransitPreferences(preferences)
        } catch is ThrowValidationError {
            return
        } catch {
            assertionFailure("Transit map validation produced an unexpected error: \(error)")
        }
    }

    private func publishNetworkIntensity(_ networkIntensityPercent: Double) {
        do {
            let preferences = try session.transitPreferences
                .replacingNetworkIntensityPercent(networkIntensityPercent)
            session.updateTransitPreferences(preferences)
        } catch is ThrowValidationError {
            return
        } catch {
            assertionFailure("Transit network validation produced an unexpected error: \(error)")
        }
    }

    private func publishMarkSize(_ markSizePercent: Double) {
        do {
            let preferences = try session.transitPreferences
                .replacingMarkSizePercent(markSizePercent)
            session.updateTransitPreferences(preferences)
        } catch is ThrowValidationError {
            return
        } catch {
            assertionFailure("Transit mark-size validation produced an unexpected error: \(error)")
        }
    }
}

#if DEBUG
    extension TransitSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Setup",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack { TransitSettingsView(session: .fixture()) }
                    .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Configured",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    TransitSettingsView(session: .transitSettingsSnapshotFixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview("Setup") {
        TransitSettingsView.snapshotPreviews
    }
#endif
