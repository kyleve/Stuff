import SFSafeSymbols
import SwiftUI
import ThrowCore

struct CalibrationStepView: View {
    @Bindable var model: OnboardingFlowModel
    @State private var showsFullScreenPreview = false

    var body: some View {
        Form {
            Section {
                outputChoiceButton(
                    .externalDisplay,
                    title: .calibrationOutputExternal,
                    detail: .calibrationOutputExternalDescription,
                    symbol: .viewfinder,
                )
                outputChoiceButton(
                    .fullScreenPreview,
                    title: .calibrationOutputFullScreen,
                    detail: .calibrationOutputFullScreenDescription,
                    symbol: .rectanglePortraitAndArrowRight,
                )

                if model.calibrationOutputChoice == .externalDisplay {
                    Label(
                        String(localized: model.hasConnectedExternalDisplay
                            ? .calibrationExternalConnected
                            : .calibrationExternalMissing),
                        systemSymbol: model.hasConnectedExternalDisplay
                            ? .checkmarkCircleFill
                            : .exclamationmarkTriangleFill,
                    )
                    .foregroundStyle(model.hasConnectedExternalDisplay ? .green : .red)
                } else if model.calibrationOutputChoice == .fullScreenPreview {
                    Button(
                        String(localized: .calibrationOpenFullScreen),
                        systemSymbol: .rectanglePortraitAndArrowRight,
                    ) {
                        showsFullScreenPreview = true
                    }
                    if model.didVerifyFullScreenPreview {
                        Label(
                            String(localized: .calibrationPreviewViewed),
                            systemSymbol: .checkmarkCircleFill,
                        )
                        .foregroundStyle(.green)
                    }
                }
            } header: {
                Text(.calibrationOutputTitle)
            } footer: {
                Text(.calibrationOutputDescription)
            }

            Section {
                CalibrationPatternView(
                    screenTopBearing: model.screenTopBearing,
                    rotation: model.rotation,
                    flipHorizontal: model.flipsHorizontally,
                    flipVertical: model.flipsVertically,
                    safeInsetPercent: model.safeInsetPercent,
                )
                .frame(minHeight: 220)
                .listRowInsets(.init())
            } header: {
                Text(.onboardingCalibrationTitle)
            } footer: {
                Text(.onboardingCalibrationDescription)
            }

            Section {
                TextField(
                    String(localized: .calibrationBearing),
                    value: $model.screenTopBearing,
                    format: .number.precision(.fractionLength(0 ... 1)),
                )
                .keyboardType(.decimalPad)
                Picker(String(localized: .calibrationRotation), selection: $model.rotation) {
                    ForEach(ScreenRotation.allCases, id: \.self) { rotation in
                        Text(rotation.rawValue, format: .number)
                            .tag(rotation)
                    }
                }
                Toggle(
                    String(localized: .calibrationFlipHorizontal),
                    isOn: $model.flipsHorizontally,
                )
                Toggle(String(localized: .calibrationFlipVertical), isOn: $model.flipsVertically)
                LabeledContent(String(localized: .calibrationInset)) {
                    Text(
                        model.safeInsetPercent / 100,
                        format: .percent.precision(.fractionLength(0)),
                    )
                }
                Slider(value: $model.safeInsetPercent, in: 0 ... 20, step: 1)
                    .accessibilityLabel(Text(.calibrationInset))
                    .accessibilityValue(
                        Text(model.safeInsetPercent / 100, format: .percent),
                    )
                if model.calibrationOutputChoice == .externalDisplay,
                   model.hasConnectedExternalDisplay
                {
                    Toggle(
                        String(localized: .calibrationVerified),
                        isOn: $model.calibrationVerified,
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: model.beginCalibration)
        .onDisappear(perform: model.endCalibration)
        .fullScreenCover(isPresented: $showsFullScreenPreview) {
            FullScreenProjectionView(
                session: model.sessionForProjection,
                outputID: model.fullScreenOutputID,
                onExit: { showsFullScreenPreview = false },
            )
            .onAppear(perform: model.markFullScreenPreviewPresented)
        }
    }

    private func outputChoiceButton(
        _ choice: OnboardingCalibrationOutputChoice,
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        symbol: SFSymbol,
    ) -> some View {
        Button {
            model.calibrationOutputChoice = choice
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
                Image(
                    systemSymbol: model.calibrationOutputChoice == choice
                        ? .checkmarkCircleFill
                        : .circle,
                )
                .foregroundStyle(
                    model.calibrationOutputChoice == choice ? Color.accentColor : .secondary,
                )
                .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.calibrationOutputChoice == choice ? .isSelected : [])
    }
}
