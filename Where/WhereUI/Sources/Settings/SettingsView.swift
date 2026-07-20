import RegionKit
import SwiftUI
import WhereCore

/// Settings tab: an iOS-Settings-style top-level list of icon rows that drill
/// into grouped sub-screens (location, regions, reminders, alerts & data
/// resolution, appearance, report year, backup, data), plus a search field that
/// filters individual settings and deep-links to the screen — and the row —
/// containing each.
///
/// The top level owns nothing but navigation; behavior lives in the sub-screens
/// (`LocationSettingsView`, `AlertsSettingsView`, …). The scene's report model and
/// the two view-scoped editing models (backup, reminders) are owned here and
/// handed down; the `WhereSession` coordinator (location) and `WhereModel` (reset)
/// come from the environment via the sub-screens.
struct SettingsView: View {
    let report: YearReportModel
    @State private var backup: BackupModel
    @State private var reminders: RemindersSettingsModel
    @State private var searchText = ""
    @State private var showRegions = false

    @Environment(WhereSession.self) private var session

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
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    ForEach(searchResults) { result in
                        searchNavigationRow(result)
                    }
                } else {
                    ForEach(SettingsListSection.allCases, id: \.self) { section in
                        Section {
                            ForEach(section.destinations, id: \.self) { destination in
                                groupNavigationRow(destination)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Strings.settingsTitle)
            .searchable(text: $searchText, prompt: Strings.settingsSearchPrompt)
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
            case .location, .alerts, .appearance, .year, .backup, .data:
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
            Label(destination.rowTitle, systemImage: destination.systemImage)
        }
    }

    /// A cheap, always-available value shown on the right of a group row; `nil`
    /// for groups without a meaningful one-line summary.
    private func subtitle(for destination: SettingsDestination) -> String? {
        switch destination {
            case .location:
                LocationStatusRow.statusTitle(
                    status: session.authorizationStatus,
                    isTracking: session.isTracking,
                )
            case .year:
                report.selectedYear.formatted(.number.grouping(.never))
            case .regions, .alerts, .appearance, .backup, .data:
                nil
        }
    }

    /// A search result row: the setting's name over its parent group.
    private func searchRow(_ result: SettingsSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
            Text(result.destination.rowTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route.destination {
            case .location:
                LocationSettingsView(focus: route.focus)
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
            case .backup:
                BackupSettingsView(backup: backup, focus: route.focus)
            case .data:
                DataSettingsView(report: report, focus: route.focus)
        }
    }

    /// Regions with days in the selected report year, so the region editor can
    /// surface a "used this year" group (grouping order only — it doesn't affect
    /// what's saved). `.other` isn't a pickable region, so it's dropped.
    private var regionsUsedThisYear: Set<Region> {
        guard let totals = report.report?.totals else { return [] }
        return Set(totals.filter { $0.key != .other && $0.value > 0 }.map(\.key))
    }
}

#if DEBUG
    #Preview {
        SettingsView(report: PreviewSupport.loadedYearReportModel())
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
            .whereBroadwayRoot()
    }
#endif
