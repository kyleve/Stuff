import Foundation
import SFSafeSymbols
import SwiftUI
import ThrowCore

struct ProjectionModeStepView: View {
    @Bindable var model: OnboardingFlowModel

    var body: some View {
        Form {
            Section {
                modeButton(.map, title: .modeMap, detail: .modeMapDescription, symbol: .map)
                modeButton(
                    .trueSky,
                    title: .modeTrueSky,
                    detail: .modeTrueSkyDescription,
                    symbol: .viewfinder,
                )
            } header: {
                Text(.onboardingModeTitle)
            } footer: {
                Text(.onboardingModeDescription)
            }

            if model.selectedMode == .map {
                Section {
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
                                Measurement(value: model.mapRadius, unit: UnitLength.nauticalMiles),
                                format: .measurement(width: .abbreviated, usage: .asProvided),
                            ),
                        )
                }
            } else if model.selectedMode == .trueSky {
                Section {
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
                                Measurement(value: model.minimumElevation, unit: UnitAngle.degrees),
                                format: .measurement(width: .abbreviated, usage: .asProvided),
                            ),
                        )
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func modeButton(
        _ mode: ProjectionMode,
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        symbol: SFSymbol,
    ) -> some View {
        Button {
            model.selectedMode = mode
        } label: {
            HStack(alignment: .top) {
                Image(systemSymbol: symbol)
                    .frame(width: 32)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemSymbol: model.selectedMode == mode ? .checkmarkCircleFill : .circle)
                    .foregroundStyle(model.selectedMode == mode ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.selectedMode == mode ? .isSelected : [])
    }
}
