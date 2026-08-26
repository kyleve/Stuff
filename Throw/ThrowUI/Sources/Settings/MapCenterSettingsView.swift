import SnapshotKit
import SwiftUI
import ThrowCore

struct MapCenterSettingsView: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Form {
            Section {
                offsetControl(
                    title: String(localized: .mapCenterEastWest),
                    value: $session.mapCenterEastOffset,
                )
                offsetControl(
                    title: String(localized: .mapCenterNorthSouth),
                    value: $session.mapCenterNorthOffset,
                )
                Button(String(localized: .mapCenterReset)) {
                    session.resetMapCenter()
                }
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
