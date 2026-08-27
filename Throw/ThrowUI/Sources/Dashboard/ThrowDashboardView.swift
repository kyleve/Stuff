import Foundation
import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct ThrowDashboardView: View {
    let session: ThrowSession
    let outputs: ControllerProjectionOutputs

    @State private var presentation: DashboardPresentation?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.throwDateProvider) private var dateProvider
    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        NavigationStack {
            List {
                if let settingsFailure = session.settingsFailure {
                    Section {
                        SettingsFailureMessage(detail: settingsFailure)
                    }
                }

                Section(String(localized: .dashboardGlobalStatus)) {
                    LabeledContent(
                        String(localized: .dashboardOutput),
                        value: session.outputHealth.localizedDescription,
                    )
                    LabeledContent(String(localized: .dashboardCalibration)) {
                        // `Label` here greedily expands the row on iOS 27.
                        HStack {
                            Image(systemSymbol: session.calibrationVerified
                                ? .checkmarkCircleFill
                                : .exclamationmarkTriangleFill)
                                .accessibilityHidden(true)
                            Text(session.calibrationVerified
                                ? .calibrationHealthVerified
                                : .calibrationHealthUnverified)
                        }
                        .foregroundStyle(session.calibrationVerified ? .green : .orange)
                    }
                    LocationHealthRow(health: session.locationHealth)
                }

                Section(String(localized: .dashboardNowProjecting)) {
                    let presentation = ProjectionExperiencePresentation(
                        id: session.activeExperienceID ?? .airAndSpace,
                    )
                    Label(presentation.name, systemSymbol: presentation.symbol)
                        .font(.headline)
                    FeedHealthRow(health: session.activeExperienceHealth)
                    LabeledContent(presentation.visibleContentLabel) {
                        Text(session.activeExperienceHealth.visibleContentCount, format: .number)
                    }
                    if let lastUpdate = session.lastUpdate {
                        LabeledContent(String(localized: .dashboardLastUpdate)) {
                            Text(verbatim: relativeDescription(for: lastUpdate))
                        }
                    }
                    if let nextRetry = session.nextRetry {
                        LabeledContent(String(localized: .dashboardNextRetry)) {
                            Text(verbatim: relativeDescription(for: nextRetry))
                        }
                    }
                    if let dwellEndsAt = session.experienceDwellEndsAt {
                        LabeledContent(String(localized: .dashboardRemainingDwell)) {
                            RemainingDwellText(end: dwellEndsAt)
                        }
                    }
                    if let nextExperienceID = session.nextExperienceID {
                        LabeledContent(
                            String(localized: .dashboardNextView),
                            value: ProjectionExperiencePresentation(id: nextExperienceID).name,
                        )
                    }
                    if let prewarmingExperienceID = session.prewarmingExperienceID {
                        LabeledContent(
                            String(localized: .dashboardPreparingView),
                            value: ProjectionExperiencePresentation(id: prewarmingExperienceID)
                                .name,
                        )
                    }
                    if let failure = session.experienceSelectionFailure {
                        Label {
                            Text(failure.localizedDescription)
                        } icon: {
                            Image(systemSymbol: .exclamationmarkTriangleFill)
                        }
                        .foregroundStyle(.red)
                    }
                    if session.experienceRotationHasControls {
                        ControlGroup {
                            Button(
                                String(localized: .dashboardPreviousView),
                                systemSymbol: .backwardFill,
                            ) {
                                Task(name: "Throw select previous View") {
                                    await session.selectPreviousExperience()
                                }
                            }
                            if session.isExperienceRotationPaused {
                                Button(
                                    String(localized: .dashboardResumeRotation),
                                    systemSymbol: .playFill,
                                ) {
                                    Task(name: "Throw resume View rotation") {
                                        await session.resumeExperienceRotation()
                                    }
                                }
                            } else {
                                Button(
                                    String(localized: .dashboardPauseRotation),
                                    systemSymbol: .pauseFill,
                                ) {
                                    Task(name: "Throw pause View rotation") {
                                        await session.pauseExperienceRotation()
                                    }
                                }
                            }
                            Button(
                                String(localized: .dashboardNextViewAction),
                                systemSymbol: .forwardFill,
                            ) {
                                Task(name: "Throw select next View") {
                                    await session.selectNextExperience()
                                }
                            }
                        }
                    }
                }

                Section(ProjectionExperiencePresentation(id: .airAndSpace).name) {
                    LabeledContent(
                        String(localized: .dashboardSource),
                        value: session.sourceDisplayName,
                    )
                    LabeledContent(String(localized: .sourceInterval)) {
                        Text(
                            Duration.seconds(session.pollingIntervalSeconds),
                            format: .time(pattern: .minuteSecond),
                        )
                    }
                    ProjectionModeControl(session: session)
                    LayerCatalogRows(session: session, experienceID: .airAndSpace)
                }

                if session.sourceChoice == .adsbExchange {
                    ADSBExchangeDashboardSection(
                        credentialState: session.rapidAPICredentialState,
                        intervalSeconds: session.pollingIntervalSeconds,
                        estimate: session.adsbExchangeUsageEstimate(
                            intervalSeconds: session.pollingIntervalSeconds,
                        ),
                    )
                }

                if session.sourceChoice == .flightradar24 {
                    Flightradar24DashboardSection(
                        credentialState: session.flightradar24CredentialState,
                        intervalSeconds: session.pollingIntervalSeconds,
                        requestsPerHour: session.adsbExchangeUsageEstimate(
                            intervalSeconds: session.pollingIntervalSeconds,
                        ).displayedRequestsPerHour,
                    )
                }

                Section(String(localized: .dashboardLocation)) {
                    Button(
                        String(localized: .dashboardRefreshLocation),
                        systemSymbol: .locationFill,
                    ) {
                        Task(name: "Throw refresh observer") {
                            await session.refreshLocation()
                        }
                    }
                    if case .offeredBest = session.locationHealth {
                        Button(
                            String(localized: .locationAcceptBest),
                            systemSymbol: .checkmarkCircle,
                        ) {
                            Task(name: "Throw accept offered observer") {
                                await session.acceptOfferedLocation()
                            }
                        }
                        Button(String(localized: .commonRetry), systemSymbol: .arrowClockwise) {
                            Task(name: "Throw retry observer") {
                                await session.refreshLocation()
                            }
                        }
                    }
                }

                if session.feedHealth == .quiet {
                    Section {
                        Button(String(localized: .quietWake30)) {
                            session.wakeQuietly(forMinutes: 30)
                        }
                        Menu {
                            Button(String(localized: .quietWake15)) {
                                session.wakeQuietly(forMinutes: 15)
                            }
                            Button(String(localized: .quietWake60)) {
                                session.wakeQuietly(forMinutes: 60)
                            }
                        } label: {
                            Text(.quietOtherWakeDurations)
                        }
                    }
                }

                Section {
                    Button(String(localized: .dashboardPreview), systemSymbol: .eye) {
                        presentation = .preview
                    }
                    Button(
                        String(localized: .dashboardProjectFullScreen),
                        systemSymbol: .rectanglePortraitAndArrowRight,
                    ) {
                        presentation = .fullScreen
                    }
                    NavigationLink(value: DashboardDestination.calibration) {
                        Label(String(localized: .dashboardCalibrate), systemSymbol: .viewfinder)
                    }
                    NavigationLink(value: DashboardDestination.settings) {
                        Label(String(localized: .dashboardSettings), systemSymbol: .gear)
                    }
                    #if DEBUG
                        NavigationLink(value: DashboardDestination.projectorLab) {
                            Label(
                                String(localized: .projectorLabTitle),
                                systemSymbol: .wrenchAndScrewdriver,
                            )
                        }
                    #endif
                }
            }
            .navigationTitle(Text(.dashboardTitle))
            .navigationDestination(for: DashboardDestination.self) { destination in
                switch destination {
                    case .settings:
                        ThrowSettingsView(session: session, outputs: outputs)
                    case .calibration:
                        CalibrationSettingsView(session: session, outputID: outputs.calibration)
                    #if DEBUG
                        case .projectorLab:
                            ProjectorLabView(session: session, outputID: outputs.projectorLab)
                    #endif
                }
            }
        }
        .fullScreenCover(item: $presentation) { presentation in
            switch presentation {
                case .preview:
                    PreviewProjectionContainer(
                        session: session,
                        outputID: outputs.preview,
                        onExit: dismissPresentation,
                    )
                case .fullScreen:
                    FullScreenProjectionView(
                        session: session,
                        outputID: outputs.fullScreen,
                        onExit: dismissPresentation,
                    )
            }
        }
    }

    private func relativeDescription(for date: Date) -> String {
        RelativeDatePresentation.string(
            for: date,
            relativeTo: dateProvider.now(),
            locale: locale,
            calendar: calendar,
        )
    }

    private func dismissPresentation() {
        presentation = nil
    }
}

private struct RemainingDwellText: View {
    let end: Date

    @Environment(\.throwDateProvider) private var dateProvider

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = max(0, Int(ceil(end.timeIntervalSince(dateProvider.now()))))
            Text(
                Duration.seconds(seconds),
                format: .time(pattern: .minuteSecond),
            )
        }
    }
}

#if DEBUG
    extension ThrowDashboardView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Healthy",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .healthyDashboardSnapshotFixture())
            }
            SnapshotCase(
                name: "Retrying With Last Good Marks",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .retryingDashboardSnapshotFixture())
            }
            SnapshotCase(
                name: "Quiet Standby",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .quietDashboardSnapshotFixture())
            }
            SnapshotCase(
                name: "ADS-B Exchange Missing Credential",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .adsbExchangeMissingCredentialSnapshotFixture())
            }
            SnapshotCase(
                name: "ADS-B Exchange Quota Reached",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .adsbExchangeQuotaSnapshotFixture())
            }
            SnapshotCase(
                name: "ADS-B Exchange Five Second Cadence",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .adsbExchangeFastCadenceSnapshotFixture())
            }
            SnapshotCase(
                name: "View Rotation Enabled",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .experienceDashboardSnapshotFixture(.rotating))
            }
            SnapshotCase(
                name: "View Rotation Paused",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .experienceDashboardSnapshotFixture(.paused))
            }
            SnapshotCase(
                name: "Prewarming Transit",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .experienceDashboardSnapshotFixture(.prewarming))
            }
            SnapshotCase(
                name: "Failed View Selection",
                configurations: focusedConfigurations,
                settle: .immediate,
            ) {
                snapshotView(session: .experienceDashboardSnapshotFixture(.failedSelection))
            }
        }

        private static var focusedConfigurations: [SnapshotConfiguration] {
            [SnapshotConfiguration(device: .iPhoneFullContent)]
        }

        private static func snapshotView(session: ThrowSession) -> some View {
            ThrowDashboardView(
                session: session,
                outputs: ControllerProjectionOutputs(namespace: snapshotNamespace),
            )
            .throwBroadwayRoot()
            .environment(\.throwDateProvider, session.dateProvider)
        }

        private static var snapshotNamespace: UUID {
            guard let value = UUID(uuidString: "D8BF4D04-9D25-459F-9CA7-D5F5BC14F503") else {
                preconditionFailure("Snapshot output namespace must be valid")
            }
            return value
        }
    }

    #Preview("Snapshot matrix") {
        ThrowDashboardView.snapshotPreviews
    }
#endif
