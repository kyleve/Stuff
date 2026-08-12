import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Settings tab: an iOS-Settings-style top-level list of icon rows that drill
/// into grouped sub-screens — a Data group at the top (attachments, logged days,
/// regions), then devices, alerts, appearance, report year, data management,
/// feature discovery, and About — plus a search field that filters individual settings and
/// deep-links to the screen — and the row — containing each.
///
/// The top level owns nothing but navigation; behavior lives in the sub-screens
/// (`DevicesSettingsView`, `AlertsSettingsView`, …). The scene's report model and
/// the two view-scoped editing models (backup, reminders) are owned here and
/// handed down; the `WhereSession` coordinator (recording/location) and
/// `WhereModel` (reset) come from the environment via the sub-screens.
struct SettingsView: View {
    let report: YearReportModel
    @State private var backup: BackupModel
    @State private var reminders: RemindersSettingsModel
    @State private var searchText = ""
    @State private var showRegions = false

    @Environment(WhereSession.self) private var session
    @Environment(WhereModel.self) private var model
    @Environment(\.lifecycle) private var lifecycle
    @Environment(\.isInDemoMode) private var isInDemoMode

    init(report: YearReportModel) {
        self.report = report
        _backup = State(initialValue: BackupModel(services: report.services))
        _reminders = State(initialValue: RemindersSettingsModel(
            services: report.services,
            preferences: report.preferences,
            now: report.now,
        ))
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !searchQuery.isEmpty
    }

    private var searchResults: [SettingsSearchResult] {
        SettingsCatalog.results(matching: searchQuery)
            .filter { isAvailable($0.destination) }
    }

    /// Whether a group is offered right now. Everything is, except the few
    /// groups a demo has no business showing (see
    /// `SettingsDestination.isAvailableInDemoMode`) — filtered here rather than
    /// per-row so the list and the search index can't disagree about what
    /// exists.
    private func isAvailable(_ destination: SettingsDestination) -> Bool {
        !isInDemoMode || destination.isAvailableInDemoMode
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    ForEach(searchResults) { result in
                        searchNavigationRow(result)
                    }
                } else {
                    if isInDemoMode {
                        demoSection
                    }
                    ForEach(SettingsListSection.allCases, id: \.self) { section in
                        let destinations = section.destinations.filter(isAvailable)
                        if !destinations.isEmpty {
                            Section {
                                ForEach(destinations, id: \.self) { destination in
                                    groupNavigationRow(destination)
                                }
                            } header: {
                                if let headerTitle = section.headerTitle {
                                    Text(headerTitle)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: .settingsTitle))
            .searchable(text: $searchText, prompt: String(localized: .settingsSearchPrompt))
            .overlay {
                if isSearching, searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showRegions) {
                RegionsSettingsView(usedThisYear: regionsUsedThisYear)
            }
        }
    }

    /// The way out of demo mode, at the very top of the list where a temporary
    /// state belongs — above the real settings rather than filed among them.
    ///
    /// No confirmation: there is nothing to lose. Demo data was never saved,
    /// and leaving is exactly what quitting the app would do anyway, so a
    /// "are you sure?" would overstate the stakes.
    private var demoSection: some View {
        Section {
            Button {
                exitDemoMode()
            } label: {
                Label(
                    String(localized: .settingsDemoExit),
                    systemSymbol: .rectanglePortraitAndArrowRight,
                )
            }
        } header: {
            Text(String(localized: .settingsDemoHeader))
        } footer: {
            Text(String(localized: .settingsDemoFooter))
        }
    }

    /// Tear the demo world down and re-drive the launch, through the same
    /// `LifecycleProxy` the reset flow uses. The relaunch parks on the
    /// onboarding gate (or resolves straight through for someone who had
    /// already onboarded before trying the demo).
    private func exitDemoMode() {
        Task { await lifecycle.teardown(WhereLaunch.exitDemoPlan(for: model), input: session) }
    }

    /// A top-level row that either pushes its sub-screen or, for a sheet group
    /// (Regions), presents it modally.
    @ViewBuilder
    private func groupNavigationRow(_ destination: SettingsDestination) -> some View {
        if destination.isSheet {
            Button { present(destination) } label: { groupRow(destination) }
                .tint(.primary)
        } else {
            NavigationLink(value: SettingsRoute(destination)) { groupRow(destination) }
        }
    }

    /// A search-result row that mirrors the group row's push-vs-sheet routing.
    @ViewBuilder
    private func searchNavigationRow(_ result: SettingsSearchResult) -> some View {
        if result.destination.isSheet {
            Button { present(result.destination) } label: { searchRow(result) }
                .tint(.primary)
        } else {
            NavigationLink(value: SettingsRoute(result)) { searchRow(result) }
        }
    }

    /// Present a sheet group. Non-sheet destinations are pushed via
    /// `NavigationLink`, so reaching them here is a programmer error.
    private func present(_ destination: SettingsDestination) {
        switch destination {
            case .regions:
                showRegions = true
            case .attachments, .loggedDays, .devices, .alerts, .appearance, .year, .siri,
                 .widgets, .shareEvidence, .insightsAccuracy, .personalization, .data, .about:
                assertionFailure("\(destination) is a push destination, not a sheet")
        }
    }

    /// A top-level drill-in row: icon + group title, with a value subtitle where
    /// one is cheap and useful (location status, the report year).
    private func groupRow(_ destination: SettingsDestination) -> some View {
        LabeledContent {
            if let subtitle = subtitle(for: destination) {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                Text(destination.rowTitle)
            } icon: {
                SettingsIcon(systemSymbol: destination.systemSymbol, color: destination.iconColor)
            }
        }
    }

    /// A cheap, always-available value shown on the right of a group row; `nil`
    /// for groups without a meaningful one-line summary.
    private func subtitle(for destination: SettingsDestination) -> String? {
        switch destination {
            case .devices:
                LocationStatusRow.statusTitle(
                    status: session.authorizationStatus,
                    isTracking: session.isTracking,
                )
            case .year:
                report.selectedYear.formatted(.number.grouping(.never))
            case .attachments, .loggedDays, .regions, .alerts, .appearance, .siri, .widgets,
                 .shareEvidence, .insightsAccuracy, .personalization, .data, .about:
                nil
        }
    }

    /// A search result row: the owning group's icon beside the setting's name
    /// over its parent group, so a result reads as belonging to its section.
    private func searchRow(_ result: SettingsSearchResult) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                Text(result.destination.rowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            SettingsIcon(
                systemSymbol: result.destination.systemSymbol,
                color: result.destination.iconColor,
            )
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route.destination {
            case .attachments:
                EvidenceListView(report: report)
            case .loggedDays:
                LoggedDaysView(report: report)
            case .devices:
                DevicesSettingsView(session: session, focus: route.focus)
            case .regions:
                // Regions is presented as a sheet (`isSheet`), so it's never
                // routed here; this arm only keeps the switch exhaustive.
                EmptyView()
            case .alerts:
                AlertsSettingsView(report: report, reminders: reminders, focus: route.focus)
            case .appearance:
                AppearanceSettingsView(report: report, focus: route.focus)
            case .year:
                VisibleYearSettingsView(report: report, focus: route.focus)
            case .siri:
                SiriFeaturesView(
                    focus: route.focus,
                    presentation: featureDiscoveryPresentation,
                )
            case .widgets:
                WidgetFeaturesView(
                    focus: route.focus,
                    presentation: featureDiscoveryPresentation,
                )
            case .shareEvidence:
                ShareEvidenceFeaturesView(
                    report: report,
                    focus: route.focus,
                    presentation: featureDiscoveryPresentation,
                )
            case .insightsAccuracy:
                InsightsAccuracyFeaturesView(
                    report: report,
                    focus: route.focus,
                    presentation: featureDiscoveryPresentation,
                )
            case .personalization:
                PersonalizationFeaturesView(report: report, focus: route.focus)
            case .data:
                DataSettingsView(report: report, backup: backup, focus: route.focus)
            case .about:
                AboutSettingsView(focus: route.focus)
        }
    }

    /// Regions with days in the selected report year, so the region editor can
    /// surface a "used this year" group (grouping order only — it doesn't affect
    /// what's saved). `.other` isn't a pickable region, so it's dropped.
    private var regionsUsedThisYear: Set<Region> {
        guard let totals = report.report?.totals else { return [] }
        return Set(totals.filter { $0.key != .other && $0.value > 0 }.map(\.key))
    }

    private var featureDiscoveryPresentation: FeatureDiscoveryPresentation {
        FeatureDiscoveryPresentation(
            report: report.report,
            selectedYear: report.selectedYear,
            referenceDate: report.referenceDate,
            calendar: report.calendar,
        )
    }
}

#if DEBUG
    extension SettingsView: SnapshotProviding {
        /// The extra right-to-left variant exercises the RTL configuration axis
        /// on a directional screen (leading labels, trailing values/toggles).
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults + [
                    SnapshotConfiguration(
                        layoutDirection: .rightToLeft,
                        device: .iPhoneFullContent,
                    ),
                ],
            ) {
                SettingsView(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
            }
            // Demo mode: the exit section on top, and the groups that would
            // reach past the demo (backup, erase/reset, app icon) gone.
            whereSnapshot(name: "DemoMode", configurations: .fullContentPhoneLightDark) {
                SettingsView(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(\.isInDemoMode, true)
            }
        }
    }

    #Preview {
        SettingsView.snapshotPreviews
    }
#endif

#if DEBUG
    extension SettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            SettingsView.self,
            title: "Settings",
            navigationContainer: .none,
            routes: [
                .push(to: EvidenceListView.flyoverID),
                .push(to: LoggedDaysView.flyoverID),
                .modal(to: RegionsSettingsView.flyoverID),
                .push(to: DevicesSettingsView.flyoverID),
                .push(to: AlertsSettingsView.flyoverID),
                .push(to: AppearanceSettingsView.flyoverID),
                .push(to: VisibleYearSettingsView.flyoverID),
                .push(to: SiriFeaturesView.flyoverID),
                .push(to: WidgetFeaturesView.flyoverID),
                .push(to: ShareEvidenceFeaturesView.flyoverID),
                .push(to: InsightsAccuracyFeaturesView.flyoverID),
                .push(to: PersonalizationFeaturesView.flyoverID),
                .push(to: DataSettingsView.flyoverID),
                .push(to: AboutSettingsView.flyoverID),
            ],
        ) { world in
            SettingsView(report: world.report)
        }
    }
#endif
