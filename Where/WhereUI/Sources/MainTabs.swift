#if DEBUG
    @_spi(Testing) import InstallerKitUI
#endif
import InstallerKit
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
@_spi(Testing) import WhereCore

/// The logged-in tab bar — the launch *destination* once the runner reaches
/// `.ready`, not a launch step. Owns the scene-scoped ``YearReportModel`` as
/// `@State` and drives its store-change subscription from `scenePhase` (active →
/// subscribe + pull, background → cancel — closing the headless-relaunch rescan
/// leak).
///
/// Locations, optional Elsewhere, Your Year, and Settings. Resolve stays in
/// the Locations toolbar; the
/// data screens (attachments, logged days, regions) live in the Settings "Data"
/// group. The tabs receive the report by explicit init injection (compile-
/// checked wiring); the always-on `WhereSession` coordinator stays in the
/// environment.
struct MainTabs: View {
    /// Identity for the tab-bar selection.
    private typealias TabID = MainTabSelection.TabID

    private struct WelcomeTaskID: Hashable {
        let isActive: Bool
        let isEnabled: Bool
    }

    @State private var report: YearReportModel
    @State private var recordingWarning: RecordingConfigurationWarningModel
    @State private var welcome: LocationWelcomeModel
    @State private var planningDestination: PlannedStaysDestination?
    @State private var selection = MainTabSelection()
    @Environment(UpdateModel.self) private var updates: UpdateModel?
    @Environment(\.isInDemoMode) private var isInDemoMode
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
        TabView(selection: $selection.selected) {
            Tab(
                String(localized: .tabLocations),
                systemSymbol: .locationFill,
                value: TabID.locations,
            ) {
                LocationsView(report: report, openElsewhere: { selection.selected = .elsewhere })
                    .reportingDeveloperTabBarInset()
            }

            if report.hasElsewhere {
                Tab(
                    String(localized: .tabElsewhere),
                    systemSymbol: .globeAmericas,
                    value: TabID.elsewhere,
                ) {
                    ElsewhereView(report: report, isSelected: selection.selected == .elsewhere)
                        .reportingDeveloperTabBarInset()
                }
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
                    updateTitle: isInDemoMode ? nil : updates?.attentionTitle,
                )
            }
            .badge((recordingWarning.isPresented ? 1 : 0) +
                ((!isInDemoMode && updates?.needsAttention == true) ? 1 : 0))
        }
        .accessibilityHidden(welcomePresentation != nil)
        .onChange(of: report.hasElsewhere, initial: true) { _, hasElsewhere in
            selection.reconcile(hasElsewhere: hasElsewhere)
        }
        .tabViewBottomAccessory(isEnabled: welcomeAccessory != nil) {
            if let welcomeAccessory {
                LocationWelcomeStatusAccessory(accessory: welcomeAccessory)
            }
        }
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
        .task(id: isUpdateCheckActive) {
            guard isUpdateCheckActive else { return }
            await updates?.refresh(force: false)
        }
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

    private var isUpdateCheckActive: Bool {
        scenePhase == .active && !isInDemoMode
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
            _selection = State(initialValue: MainTabSelection(selected: selection))
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
            } + [elsewhereSnapshot(), elsewhereSnapshot(theme: .alternate)]
        }

        private static func elsewhereSnapshot(theme: WhereTheme = .standard) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            let session = PreviewSupport.loadedSession()
            session.preferences.showsLocationWelcome = false
            let report = YearReportModel(
                services: session.services,
                selectedYear: PreviewSupport.year,
                preferences: session.preferences,
                now: session.now,
            )
            let welcome = LocationWelcomeModel(
                services: session.services,
                preferences: session.preferences,
                now: session.now,
            )
            return whereSnapshot(
                name: theme == .standard ? "Elsewhere" : "FlatElsewhere",
                configurations: theme == .standard ? .fullContentScreenDefaults :
                    .fullContentPhoneLightDark,
                theme: theme,
                onReadyToMeasure: {
                    try! await session.services.setPrimaryRegions([
                        PrimaryRegion(region: .california, appearance: nil, order: 0),
                        PrimaryRegion(region: .newYork, appearance: nil, order: 1),
                    ])
                    let nevada = Region(rawValue: "us-NV")!
                    let oregon = Region(rawValue: "us-OR")!
                    for day in [
                        DayPresence(
                            day: CalendarDay(year: PreviewSupport.year, month: 6, day: 1),
                            regions: [nevada],
                        ),
                        DayPresence(
                            day: CalendarDay(year: PreviewSupport.year, month: 6, day: 2),
                            regions: [nevada, oregon],
                        ),
                    ] {
                        try! await session.services.journal.addManualDay(
                            date: day.day.startOfDay(in: report.calendar),
                            regions: day.regions,
                            audit: nil,
                        )
                    }
                    await report.refresh()
                    if let input = report.elsewhereInput { await report.elsewhere.refresh(input) }
                },
                onReadyToSnapshot: {
                    await PreviewSupport.loadCardArtwork(
                        for: report.elsewhere.content(for: report.selectedYear)?.regions
                            .map(\.region) ?? [],
                        cache: cache,
                    )
                },
            ) {
                PreparedElsewhereSnapshot(session: session, report: report, welcome: welcome)
                    .environment(\.regionOutlinePathCache, cache)
            }
        }

        /// Observe readiness in a View body, not in the one-time SnapshotCase factory.
        private struct PreparedElsewhereSnapshot: View {
            let session: WhereSession
            let report: YearReportModel
            let welcome: LocationWelcomeModel

            var body: some View {
                if report.loadState == .loaded {
                    MainTabs(
                        session: session,
                        report: report,
                        welcome: welcome,
                        selection: .elsewhere,
                    )
                    .environment(session)
                    .environment(\.scenePhase, .inactive)
                } else {
                    ProgressView()
                }
            }
        }

        private static func snapshotCases(
            configurations: [SnapshotConfiguration],
            settle: SnapshotSettle,
        ) -> [SnapshotCase] {
            [
                snapshot(
                    name: "UpdateAvailable",
                    configurations: configurations,
                    settle: settle,
                    selection: .year,
                    updates: InstallerPreview.model(.available),
                    configure: { _ in },
                ),
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
            theme: WhereTheme = .standard,
            updates: UpdateModel? = nil,
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
                    primaryRegions: [.california, .newYork],
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
                theme: theme,
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
                .environment(updates)
                .environment(\.scenePhase, updates == nil ? .inactive : .active)
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
