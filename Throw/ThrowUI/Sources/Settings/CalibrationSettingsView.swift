import SFSafeSymbols
import SwiftUI
import ThrowCore

struct CalibrationSettingsView: View {
    @Bindable var session: ThrowSession
    let outputID: ProjectionOutputID

    var body: some View {
        Form {
            if let settingsFailure = session.settingsFailure {
                Section {
                    SettingsFailureMessage(detail: settingsFailure)
                }
            }
            CalibrationPatternView(
                screenTopBearing: session.screenTopBearing,
                rotation: session.screenRotation,
                flipHorizontal: session.flipHorizontal,
                flipVertical: session.flipVertical,
                safeInsetPercent: session.safeInsetPercent,
            )
            .frame(minHeight: 260)
            .listRowInsets(.init())

            Section {
                TextField(
                    String(localized: .calibrationBearing),
                    value: $session.screenTopBearing,
                    format: .number.precision(.fractionLength(0 ... 1)),
                )
                .keyboardType(.decimalPad)
                Picker(
                    String(localized: .calibrationRotation),
                    selection: $session.screenRotation,
                ) {
                    ForEach(ScreenRotation.allCases, id: \.self) { rotation in
                        Text(rotation.rawValue, format: .number).tag(rotation)
                    }
                }
                Toggle(String(localized: .calibrationFlipHorizontal), isOn: $session.flipHorizontal)
                Toggle(String(localized: .calibrationFlipVertical), isOn: $session.flipVertical)
                LabeledContent(String(localized: .calibrationInset)) {
                    Text(session.safeInsetPercent / 100, format: .percent)
                }
                Slider(value: $session.safeInsetPercent, in: 0 ... 20, step: 1)
                    .accessibilityLabel(Text(.calibrationInset))
                    .accessibilityValue(
                        Text(session.safeInsetPercent / 100, format: .percent),
                    )
                Toggle(String(localized: .calibrationVerified), isOn: $session.calibrationVerified)
                    .disabled(
                        session.hasExternalDisplayOutput == false
                            && session.calibrationVerified == false,
                    )
                if session.hasExternalDisplayOutput == false {
                    Label(
                        String(localized: .calibrationVerificationRequiresExternal),
                        systemSymbol: .exclamationmarkTriangleFill,
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(Text(.calibrationTitle))
        .onAppear {
            session.projectionOutputConnected(.calibration(outputID))
        }
        .onDisappear {
            session.projectionOutputDisconnected(.calibration(outputID))
        }
    }
}
