import Foundation
import SwiftUI
import ThrowCore

struct ProjectionModeControl: View {
    private let session: ThrowSession
    @State private var model: ProjectionViewportSettingsModel

    init(session: ThrowSession) {
        self.session = session
        _model = State(initialValue: ProjectionViewportSettingsModel(session: session))
    }

    var body: some View {
        Group {
            Picker(String(localized: .settingsMode), selection: $model.projectionMode) {
                Text(.modeMap).tag(ProjectionMode.map)
                Text(.modeTrueSky).tag(ProjectionMode.trueSky)
            }
            .pickerStyle(.segmented)

            switch model.projectionMode {
                case .map:
                    LabeledContent(String(localized: .viewportMapRadius)) {
                        Text(
                            Measurement(value: model.mapRadius, unit: UnitLength.nauticalMiles),
                            format: .measurement(
                                width: .abbreviated,
                                usage: .asProvided,
                                numberFormatStyle: .number.precision(.fractionLength(0)),
                            ),
                        )
                    }
                    Slider(value: $model.mapRadius, in: 5 ... 240, step: 5)
                        .accessibilityLabel(Text(.viewportMapRadius))
                        .accessibilityValue(
                            Text(
                                Measurement(
                                    value: model.mapRadius,
                                    unit: UnitLength.nauticalMiles,
                                ),
                                format: .measurement(width: .abbreviated, usage: .asProvided),
                            ),
                        )
                case .trueSky:
                    LabeledContent(String(localized: .viewportMinimumElevation)) {
                        Text(
                            Measurement(value: model.minimumElevation, unit: UnitAngle.degrees),
                            format: .measurement(
                                width: .abbreviated,
                                usage: .asProvided,
                                numberFormatStyle: .number.precision(.fractionLength(0)),
                            ),
                        )
                    }
                    Slider(value: $model.minimumElevation, in: 0 ... 45, step: 1)
                        .accessibilityLabel(Text(.viewportMinimumElevation))
                        .accessibilityValue(
                            Text(
                                Measurement(
                                    value: model.minimumElevation,
                                    unit: UnitAngle.degrees,
                                ),
                                format: .measurement(width: .abbreviated, usage: .asProvided),
                            ),
                        )
            }
        }
        .onChange(of: session.projectionMode) { _, projectionMode in
            model.projectionMode = projectionMode
        }
        .onChange(of: session.mapRadius) { _, mapRadius in
            model.mapRadius = mapRadius
        }
        .onChange(of: session.minimumElevation) { _, minimumElevation in
            model.minimumElevation = minimumElevation
        }
    }
}
