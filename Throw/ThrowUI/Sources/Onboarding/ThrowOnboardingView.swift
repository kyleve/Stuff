import Foundation
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import ThrowCore

struct ThrowOnboardingView: View {
    @State private var model: OnboardingFlowModel
    @Environment(\.throwStylesheet) private var stylesheet

    init(session: ThrowSession, outputs: ControllerProjectionOutputs) {
        _model = State(initialValue: OnboardingFlowModel(session: session, outputs: outputs))
    }

    var body: some View {
        VStack(spacing: stylesheet.spacing.large) {
            ProgressView(value: model.progress)
                .accessibilityLabel(Text(.onboardingProgress))
                .padding(.horizontal, stylesheet.spacing.large)

            if let settingsFailure = model.settingsFailure {
                SettingsFailureMessage(detail: settingsFailure)
                    .padding(.horizontal, stylesheet.spacing.large)
            }

            OnboardingStepView(model: model)
                .frame(maxWidth: 720, maxHeight: .infinity)

            HStack(spacing: stylesheet.spacing.medium) {
                if model.step != .welcome {
                    Button(String(localized: .onboardingBack), systemSymbol: .chevronLeft) {
                        model.moveBack()
                    }
                    .controlSize(.large)
                }
                Spacer()
                Button(
                    String(localized: model.step == .ready ? .onboardingStart : .commonContinue),
                    action: advance,
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.canContinue == false)
            }
            .padding(.horizontal, stylesheet.spacing.large)
            .padding(.bottom, stylesheet.spacing.large)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func advance() {
        Task(name: "Throw onboarding advance") {
            await model.advance()
        }
    }
}

#if DEBUG
    extension ThrowOnboardingView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "adsb.lol Source",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(for: .adsbLolSource)
            }
            SnapshotCase(
                name: "Local readsb Source",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(for: .readsbSource)
            }
            SnapshotCase(
                name: "ADS-B Exchange Source",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(for: .adsbExchangeSource)
            }
            SnapshotCase(
                name: "True Sky Projection",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(for: .trueSkyProjection)
            }
            SnapshotCase(
                name: "Full Screen Calibration",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(for: .fullScreenCalibration)
            }
            SnapshotCase(
                name: "Invalid Quiet Schedule",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(for: .invalidQuietSchedule)
            }
            SnapshotCase(
                name: "Ready Summary",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(for: .readySummary)
            }
        }

        private static var focusedConfigurations: [SnapshotConfiguration] {
            [SnapshotConfiguration(device: .iPhoneFullContent)]
        }

        private static func snapshotView(for scenario: SnapshotScenario) -> some View {
            let session = ThrowSession.onboardingFixture()
            let outputs = ControllerProjectionOutputs(namespace: snapshotNamespace)
            let model = OnboardingFlowModel(session: session, outputs: outputs)
            configure(model, session: session, for: scenario)
            return ThrowOnboardingView(snapshotModel: model)
                .throwBroadwayRoot()
                .environment(\.throwDateProvider, session.dateProvider)
        }

        private static func configure(
            _ model: OnboardingFlowModel,
            session: ThrowSession,
            for scenario: SnapshotScenario,
        ) {
            switch scenario {
                case .adsbLolSource:
                    model.step = .source
                    model.sourceChoice = .adsbLol
                case .readsbSource:
                    model.step = .source
                    model.sourceChoice = .readsb
                case .adsbExchangeSource:
                    model.step = .source
                    model.sourceChoice = .adsbExchange
                    model.pollingIntervalSeconds = 10
                    session.rapidAPICredentialState = .missing
                case .trueSkyProjection:
                    model.step = .projection
                    model.selectedMode = .trueSky
                    model.minimumElevation = 15
                case .fullScreenCalibration:
                    model.step = .calibration
                    model.calibrationOutputChoice = .fullScreenPreview
                    model.screenTopBearing = 287
                    model.rotation = .degrees90
                    model.flipsHorizontally = true
                    model.safeInsetPercent = 12
                case .invalidQuietSchedule:
                    model.step = .appearance
                    model.quietEnabled = true
                    model.quietStart = snapshotTime(hour: 22, minute: 0, calendar: session.calendar)
                    model.quietEnd = model.quietStart
                case .readySummary:
                    session.rapidAPICredentialState = .saved(lastFour: "4242")
                    session.locationHealth = .confirmed(
                        accuracyMeters: 18,
                        acceptedAt: session.dateProvider.now(),
                    )
                    model.step = .ready
                    model.sourceChoice = .adsbExchange
                    model.pollingIntervalSeconds = 60
                    model.seedValidatedSourceForSnapshot(
                        adsbExchangeConfiguration(intervalSeconds: 60),
                    )
                    model.selectedMode = .trueSky
                    model.minimumElevation = 12
                    model.calibrationOutputChoice = .fullScreenPreview
                    model.markFullScreenPreviewPresented()
                    model.screenTopBearing = 287
                    model.rotation = .degrees90
                    model.flipsHorizontally = true
                    model.safeInsetPercent = 8
                    model.quietEnabled = true
                    model.quietStart = snapshotTime(
                        hour: 22,
                        minute: 0,
                        calendar: session.calendar,
                    )
                    model.quietEnd = snapshotTime(
                        hour: 7,
                        minute: 0,
                        calendar: session.calendar,
                    )
            }
        }

        private static func adsbExchangeConfiguration(
            intervalSeconds: Int,
        ) -> AircraftSourceConfiguration {
            let pollingInterval: PollingInterval
            do {
                pollingInterval = try PollingInterval(seconds: intervalSeconds)
            } catch {
                preconditionFailure("Snapshot polling interval must be valid: \(error)")
            }
            return .adsbExchangeRapidAPI(
                ADSBExchangeConfiguration(
                    pollingInterval: pollingInterval,
                ),
            )
        }

        private static func snapshotTime(
            hour: Int,
            minute: Int,
            calendar: Calendar,
        ) -> Date {
            let components = DateComponents(
                calendar: calendar,
                year: 2026,
                month: 8,
                day: 24,
                hour: hour,
                minute: minute,
            )
            guard let date = calendar.date(from: components) else {
                preconditionFailure("Snapshot quiet time must be valid")
            }
            return date
        }

        private static var snapshotNamespace: UUID {
            guard let value = UUID(uuidString: "13A8D063-F189-42D3-85CE-70881ED80724") else {
                preconditionFailure("Snapshot output namespace must be valid")
            }
            return value
        }

        private init(snapshotModel: OnboardingFlowModel) {
            _model = State(initialValue: snapshotModel)
        }

        private enum SnapshotScenario {
            case adsbLolSource
            case readsbSource
            case adsbExchangeSource
            case trueSkyProjection
            case fullScreenCalibration
            case invalidQuietSchedule
            case readySummary
        }
    }

    #Preview("Snapshot matrix") {
        ThrowOnboardingView.snapshotPreviews
    }
#endif
