import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// The logged-in tab bar — the launch *destination* once the runner reaches
/// `.ready`, not a launch step. Owns the scene-scoped ``YearReportModel`` as
/// `@State` and drives its store-change subscription from `scenePhase` (active →
/// subscribe + pull, background → cancel — closing the headless-relaunch rescan
/// leak).
///
/// Three fixed tabs — Locations, Your Year, Settings. Elsewhere is folded into
/// Locations (an entry card) and Resolve into a Locations toolbar button; the
/// data screens (attachments, logged days, regions) live in the Settings "Data"
/// group. The tabs receive the report by explicit init injection (compile-
/// checked wiring); the always-on `WhereSession` coordinator stays in the
/// environment.
struct MainTabs: View {
    /// Identity for the tab-bar selection.
    private enum TabID: Hashable {
        case locations
        case year
        case settings
    }

    private struct WelcomeTaskID: Hashable {
        let isActive: Bool
        let isEnabled: Bool
    }

    @State private var report: YearReportModel
    @State private var recordingWarning: RecordingConfigurationWarningModel
    @State private var welcome: LocationWelcomeModel
    @State private var planningDestination: PlannedStaysDestination?
    @State private var selection: TabID = .locations
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.stylesheet) private var stylesheet
    private let recordingWarningSource: RecordingConfigurationWarningModel.Source
    private let allowsWelcomeLookup: Bool

    /// Build the scene's report model from the coordinator's service layer.
    /// `initialDetails` / `selectedYear` are the preview/test seam threaded from
    /// `WhereModel`; both are nil / the current year in the app.
    init(session: WhereSession, initialDetails: YearReportDetails?, selectedYear: Int) {
        let recordingWarningSource = RecordingConfigurationWarningModel.Source(session: session)
        self.recordingWarningSource = recordingWarningSource
        allowsWelcomeLookup = true
        _report = State(initialValue: YearReportModel(
            services: session.services,
            details: initialDetails,
            selectedYear: selectedYear,
            preferences: session.preferences,
            now: session.now,
        ))
        _recordingWarning = State(initialValue: RecordingConfigurationWarningModel(
            preferences: recordingWarningSource.preferences,
        ))
        _welcome = State(initialValue: LocationWelcomeModel(
            services: session.services,
            preferences: session.preferences,
            now: session.now,
        ))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(
                String(localized: .tabLocations),
                systemSymbol: .locationFill,
                value: TabID.locations,
            ) {
                LocationsView(report: report)
                    .reportingDeveloperTabBarInset()
            }

            Tab(String(localized: .tabYear), systemSymbol: .calendar, value: TabID.year) {
                YearView(report: report)
                    .reportingDeveloperTabBarInset()
            }

            Tab(value: TabID.settings) {
                SettingsView(report: report, recordingWarning: recordingWarning)
                    .reportingDeveloperTabBarInset()
            } label: {
                RecordingConfigurationWarningTabLabel(
                    model: recordingWarning,
                    source: recordingWarningSource,
                )
            }
            .badge(recordingWarning.isPresented ? 1 : 0)
        }
        .accessibilityHidden(welcomePresentation != nil)
        .modifier(LocationWelcomeAccessoryModifier(accessory: welcomeAccessory))
        // Keep the tab bar fixed — don't minimize it as content scrolls.
        .tabBarMinimizeBehavior(.never)
        .overlay {
            LocationWelcomeOverlay(
                presentation: welcomePresentation,
                dismissAction: welcome.dismiss,
                planStayAction: welcomePlanStayAction,
            )
        }
        // Subscribe + pull once the scene is on screen, and again whenever it
        // returns to the foreground; cancel the subscription on background so a
        // backgrounded scene drives no refreshes.
        .task { await report.activate() }
        .task(id: welcomeTaskID) {
            guard allowsWelcomeLookup else { return }
            guard welcomeTaskID.isEnabled else {
                welcome.resetIfDisabled()
                return
            }
            guard welcomeTaskID.isActive else { return }
            await welcome.resolve()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
                case .active:
                    Task { await report.activate() }
                case .background:
                    report.deactivate()
                case .inactive:
                    break
                @unknown default:
                    break
            }
        }
        .sheet(item: $planningDestination) { destination in
            PlannedStaysDestinationView(destination: destination, report: report)
        }
    }

    private var welcomeTaskID: WelcomeTaskID {
        WelcomeTaskID(
            isActive: scenePhase == .active,
            isEnabled: report.showsLocationWelcome,
        )
    }

    private var welcomePresentation: LocationWelcomeModel.Presentation? {
        guard report.showsLocationWelcome else { return nil }
        return welcome.presentation
    }

    private var welcomeAccessory: LocationWelcomeModel.Accessory? {
        guard report.showsLocationWelcome, welcomePresentation == nil else { return nil }
        return welcome.accessory
    }

    private var welcomePlanStayAction: ((Region) -> Void)? {
        guard report.showsEstimatedTimeAndPlanning else { return nil }
        return planStayFromWelcome
    }

    private func planStayFromWelcome(_ region: Region) {
        withAnimation(stylesheet.locationWelcome.motion.departure.animation) {
            welcome.dismiss()
        } completion: {
            planningDestination = .new(region)
        }
    }

    #if DEBUG
        private init(
            session: WhereSession,
            report: YearReportModel,
            welcome: LocationWelcomeModel,
            selection: TabID,
        ) {
            let recordingWarningSource = RecordingConfigurationWarningModel.Source(session: session)
            self.recordingWarningSource = recordingWarningSource
            allowsWelcomeLookup = false
            _report = State(initialValue: report)
            _recordingWarning = State(initialValue: RecordingConfigurationWarningModel(
                preferences: recordingWarningSource.preferences,
            ))
            _welcome = State(initialValue: welcome)
            _selection = State(initialValue: selection)
        }
    #endif
}

#if DEBUG
    extension MainTabs: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let fastConfigurations: [SnapshotConfiguration] = .phoneLightDark + [
                SnapshotConfiguration(device: .iPhone, snapshotType: .accessibility),
            ]
            let largeTypeConfigurations = [
                SnapshotConfiguration(dynamicType: .accessibility5, device: .iPhone),
            ]
            return fastConfigurations.flatMap { configuration in
                snapshotCases(configurations: [configuration], settle: .settled)
            } + largeTypeConfigurations.flatMap { configuration in
                snapshotCases(
                    configurations: [configuration],
                    settle: .settledAtLeast(minDuration: 1.0),
                )
            }
        }

        private static func snapshotCases(
            configurations: [SnapshotConfiguration],
            settle: SnapshotSettle,
        ) -> [SnapshotCase] {
            [
                snapshot(
                    name: "WelcomeLocations",
                    configurations: configurations,
                    settle: settle,
                    selection: .locations,
                ) { welcome in
                    welcome.presentForTesting(region: .newYork, greeting: .returnVisit)
                },
                snapshot(
                    name: "WelcomeYear",
                    configurations: configurations,
                    settle: settle,
                    selection: .year,
                ) { welcome in
                    welcome.presentForTesting(region: .newYork, greeting: .returnVisit)
                },
                snapshot(
                    name: "WelcomeLocating",
                    configurations: configurations,
                    settle: settle,
                    selection: .year,
                ) { welcome in
                    welcome.showLocatingForTesting()
                },
                snapshot(
                    name: "WelcomeActionRequired",
                    configurations: configurations,
                    settle: settle,
                    selection: .year,
                ) { welcome in
                    welcome.showPreciseLocationActionForTesting()
                },
            ]
        }

        private static func snapshot(
            name: String,
            configurations: [SnapshotConfiguration],
            settle: SnapshotSettle,
            selection: TabID,
            configure: (LocationWelcomeModel) -> Void,
        ) -> SnapshotCase {
            // Shell snapshots use January to avoid unrelated long-calendar scrolling.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let snapshotNow = calendar.date(from: DateComponents(
                year: PreviewSupport.year,
                month: 1,
                day: 15,
                hour: 12,
            ))!
            let session = PreviewSupport.loadedSession(now: { snapshotNow })
            // Match the fixture store before mounting the tab container so a
            // loading transition cannot race the calendar's initial positioning.
            let report = YearReportModel(
                services: session.services,
                details: YearReportDetails(
                    report: YearReport(year: PreviewSupport.year, days: [], totals: [:]),
                    primaryRegionLocations: [:],
                ),
                selectedYear: PreviewSupport.year,
                preferences: session.preferences,
                now: session.now,
            )
            let welcome = LocationWelcomeModel(
                services: session.services,
                preferences: session.preferences,
                now: session.now,
            )
            configure(welcome)
            return whereSnapshot(
                name: name,
                configurations: configurations,
                measurementReadiness: .immediate,
                settle: settle,
                onReadyToSnapshot: { await report.activate() },
            ) {
                MainTabs(
                    session: session,
                    report: report,
                    welcome: welcome,
                    selection: selection,
                )
                .environment(session)
            }
        }
    }

    private struct MainTabsPreview: View {
        private let session = PreviewSupport.loadedSession()

        var body: some View {
            MainTabs(
                session: session,
                initialDetails: PreviewSupport.sampleYearReportDetails(),
                selectedYear: PreviewSupport.year,
            )
            .environment(session)
            .whereBroadwayRoot()
        }
    }

    #Preview {
        MainTabsPreview()
    }
#endif
