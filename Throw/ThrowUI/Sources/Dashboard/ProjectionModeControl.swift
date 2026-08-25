import Foundation
import SwiftUI
import ThrowCore

struct ProjectionModeControl: View {
    @Bindable var session: ThrowSession

    var body: some View {
        Picker(String(localized: .settingsMode), selection: $session.projectionMode) {
            Text(.modeMap).tag(ProjectionMode.map)
            Text(.modeTrueSky).tag(ProjectionMode.trueSky)
        }
        .pickerStyle(.segmented)

        switch session.projectionMode {
            case .map:
                LabeledContent(String(localized: .viewportMapRadius)) {
                    Text(
                        Measurement(value: session.mapRadius, unit: UnitLength.nauticalMiles),
                        format: .measurement(
                            width: .abbreviated,
                            usage: .asProvided,
                            numberFormatStyle: .number.precision(.fractionLength(0)),
                        ),
                    )
                }
                Slider(value: $session.mapRadius, in: 5 ... 240, step: 5)
                    .accessibilityLabel(Text(.viewportMapRadius))
                    .accessibilityValue(
                        Text(
                            Measurement(value: session.mapRadius, unit: UnitLength.nauticalMiles),
                            format: .measurement(width: .abbreviated, usage: .asProvided),
                        ),
                    )
            case .trueSky:
                LabeledContent(String(localized: .viewportMinimumElevation)) {
                    Text(
                        Measurement(value: session.minimumElevation, unit: UnitAngle.degrees),
                        format: .measurement(
                            width: .abbreviated,
                            usage: .asProvided,
                            numberFormatStyle: .number.precision(.fractionLength(0)),
                        ),
                    )
                }
                Slider(value: $session.minimumElevation, in: 0 ... 45, step: 1)
                    .accessibilityLabel(Text(.viewportMinimumElevation))
                    .accessibilityValue(
                        Text(
                            Measurement(
                                value: session.minimumElevation,
                                unit: UnitAngle.degrees,
                            ),
                            format: .measurement(width: .abbreviated, usage: .asProvided),
                        ),
                    )
        }
    }
}
