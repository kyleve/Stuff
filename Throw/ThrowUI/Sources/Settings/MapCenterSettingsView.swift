import SnapshotKit
import SwiftUI
import ThrowCore

struct MapCenterSettingsView: View {
    private let session: ThrowSession
    @State private var eastOffset: Double
    @State private var northOffset: Double

    init(session: ThrowSession) {
        self.session = session
        _eastOffset = State(initialValue: session.mapCenterEastOffset)
        _northOffset = State(initialValue: session.mapCenterNorthOffset)
    }

    var body: some View {
        Form {
            Section {
                offsetControl(
                    title: String(localized: .mapCenterEastWest),
                    value: $eastOffset,
                )
                offsetControl(
                    title: String(localized: .mapCenterNorthSouth),
                    value: $northOffset,
                )
                Button(String(localized: .mapCenterReset), action: resetMapCenter)
                    .disabled(session.hasCustomMapCenter == false)
            } footer: {
                Text(.mapCenterExplanation)
            }

            Section {
                LabeledContent(String(localized: .mapCenterLatitude)) {
                    Text(
                        session.activeMapCenter.latitude,
                        format: .number.precision(.fractionLength(3)),
                    )
                    .monospacedDigit()
                }
                LabeledContent(String(localized: .mapCenterLongitude)) {
                    Text(
                        session.activeMapCenter.longitude,
                        format: .number.precision(.fractionLength(3)),
                    )
                    .monospacedDigit()
                }
            } footer: {
                Text(.mapCenterObserverMarkerExplanation)
            }
        }
        .navigationTitle(Text(.settingsMapCenter))
        .onChange(of: eastOffset) { _, eastOffset in
            publishMapCenterOffset(
                east: eastOffset,
                north: session.mapCenterNorthOffset,
            )
        }
        .onChange(of: northOffset) { _, northOffset in
            publishMapCenterOffset(
                east: session.mapCenterEastOffset,
                north: northOffset,
            )
        }
        .onChange(of: session.mapCenterEastOffset) { _, value in
            eastOffset = value
        }
        .onChange(of: session.mapCenterNorthOffset) { _, value in
            northOffset = value
        }
    }

    private func offsetControl(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title) {
                Text(
                    Measurement(value: value.wrappedValue, unit: UnitLength.nauticalMiles),
                    format: .measurement(
                        width: .abbreviated,
                        usage: .asProvided,
                        numberFormatStyle: .number.precision(.fractionLength(0)),
                    ),
                )
                .monospacedDigit()
            }
            Slider(value: value, in: -50 ... 50, step: 5)
                .accessibilityLabel(title)
                .accessibilityValue(
                    Text(
                        Measurement(value: value.wrappedValue, unit: UnitLength.nauticalMiles),
                        format: .measurement(width: .wide, usage: .asProvided),
                    ),
                )
        }
    }

    private func publishMapCenterOffset(east: Double, north: Double) {
        do {
            let offset = try MapCenterOffset(
                eastNauticalMiles: east,
                northNauticalMiles: north,
            )
            session.updateMapCenterOffset(offset)
        } catch is ThrowValidationError {
            return
        } catch {
            assertionFailure("Map-center validation produced an unexpected error: \(error)")
        }
    }

    private func resetMapCenter() {
        session.resetMapCenter()
        eastOffset = 0
        northOffset = 0
    }
}

#if DEBUG
    extension MapCenterSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Default",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                settle: .immediate,
            ) {
                NavigationStack {
                    MapCenterSettingsView(session: .fixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        MapCenterSettingsView.snapshotPreviews
    }
#endif
