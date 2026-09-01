import SFSafeSymbols
import SwiftUI
import ThrowCore

struct CalibrationSettingsView: View {
    private let session: ThrowSession
    let outputID: ProjectionOutputID
    @State private var screenTopBearing: Double
    @State private var screenRotation: ScreenRotation
    @State private var flipHorizontal: Bool
    @State private var flipVertical: Bool
    @State private var safeInsetPercent: Double
    @State private var calibrationVerified: Bool

    init(session: ThrowSession, outputID: ProjectionOutputID) {
        self.session = session
        self.outputID = outputID
        let calibration = session.globalPreferences.calibration
        _screenTopBearing = State(initialValue: calibration.screenTopBearing.degrees)
        _screenRotation = State(initialValue: calibration.rotation)
        _flipHorizontal = State(initialValue: calibration.flipHorizontal)
        _flipVertical = State(initialValue: calibration.flipVertical)
        _safeInsetPercent = State(initialValue: calibration.safeInsetFraction * 100)
        _calibrationVerified = State(
            initialValue: calibration.verifiedOnExternalDisplay,
        )
    }

    var body: some View {
        let failures = session.postLaunchFailures(for: .calibration)
        Form {
            if failures.isEmpty == false {
                Section {
                    SettingsFailureMessages(failures: failures)
                }
            }
            CalibrationPatternView(
                screenTopBearing: screenTopBearing,
                rotation: screenRotation,
                flipHorizontal: flipHorizontal,
                flipVertical: flipVertical,
                safeInsetPercent: safeInsetPercent,
            )
            .frame(minHeight: 260)
            .listRowInsets(.init())

            Section {
                TextField(
                    String(localized: .calibrationBearing),
                    value: $screenTopBearing,
                    format: .number.precision(.fractionLength(0 ... 1)),
                )
                .keyboardType(.decimalPad)
                Picker(
                    String(localized: .calibrationRotation),
                    selection: $screenRotation,
                ) {
                    ForEach(ScreenRotation.allCases, id: \.self) { rotation in
                        Text(rotation.rawValue, format: .number).tag(rotation)
                    }
                }
                Toggle(String(localized: .calibrationFlipHorizontal), isOn: $flipHorizontal)
                Toggle(String(localized: .calibrationFlipVertical), isOn: $flipVertical)
                LabeledContent(String(localized: .calibrationInset)) {
                    Text(safeInsetPercent / 100, format: .percent)
                }
                Slider(value: $safeInsetPercent, in: 0 ... 20, step: 1)
                    .accessibilityLabel(Text(.calibrationInset))
                    .accessibilityValue(
                        Text(safeInsetPercent / 100, format: .percent),
                    )
                Toggle(String(localized: .calibrationVerified), isOn: $calibrationVerified)
                    .disabled(
                        session.hasExternalDisplayOutput == false
                            && calibrationVerified == false,
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
        .onChange(of: screenTopBearing) { _, value in publishBearing(value) }
        .onChange(of: screenRotation) { _, value in
            publishCalibration(session.globalPreferences.calibration.replacingRotation(value))
        }
        .onChange(of: flipHorizontal) { _, value in
            publishCalibration(
                session.globalPreferences.calibration.replacingFlipHorizontal(value),
            )
        }
        .onChange(of: flipVertical) { _, value in
            publishCalibration(
                session.globalPreferences.calibration.replacingFlipVertical(value),
            )
        }
        .onChange(of: safeInsetPercent) { _, value in publishSafeInsetPercent(value) }
        .onChange(of: calibrationVerified) { _, value in
            publishCalibration(
                session.globalPreferences.calibration
                    .replacingVerifiedOnExternalDisplay(value),
            )
        }
        .onChange(of: session.globalPreferences.calibration) { _, calibration in
            synchronizeDraft(with: calibration)
        }
        .onAppear {
            session.projectionOutputConnected(.calibration(outputID))
        }
        .onDisappear {
            session.projectionOutputDisconnected(.calibration(outputID))
        }
    }

    private func publishBearing(_ degrees: Double) {
        do {
            let calibration = try session.globalPreferences.calibration.replacingScreenTopBearing(
                Bearing(degrees: degrees),
            )
            publishCalibration(calibration)
        } catch is ThrowValidationError {
            return
        } catch {
            assertionFailure("Bearing validation produced an unexpected error: \(error)")
        }
    }

    private func publishSafeInsetPercent(_ percent: Double) {
        do {
            let calibration = try session.globalPreferences.calibration
                .replacingSafeInsetFraction(percent / 100)
            publishCalibration(calibration)
        } catch is ThrowValidationError {
            return
        } catch {
            assertionFailure("Safe-inset validation produced an unexpected error: \(error)")
        }
    }

    private func publishCalibration(_ calibration: ProjectionCalibration) {
        let preferences = session.globalPreferences.replacingCalibration(calibration)
        session.updateGlobalPreferences(preferences)
    }

    private func synchronizeDraft(with calibration: ProjectionCalibration) {
        screenTopBearing = calibration.screenTopBearing.degrees
        screenRotation = calibration.rotation
        flipHorizontal = calibration.flipHorizontal
        flipVertical = calibration.flipVertical
        safeInsetPercent = calibration.safeInsetFraction * 100
        calibrationVerified = calibration.verifiedOnExternalDisplay
    }
}
