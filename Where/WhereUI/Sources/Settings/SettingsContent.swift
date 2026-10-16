import LifecycleKitUI
import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// An embedded demo has no app lifecycle to exit. Its host owns dismissal.
enum DemoExitPresentation {
    case session
    case embedded
}

extension EnvironmentValues {
    @Entry var demoExitPresentation = DemoExitPresentation.session
}

/// Shared searchable Settings list. Its host supplies navigation and sheet presentation.
struct SettingsContent: View {
    let report: YearReportModel
    let recordingWarning: RecordingConfigurationWarningModel
    @State private var navigation: SceneNavigationModel.Settings
    @Environment(WhereSession.self) private var session
    @Environment(WhereModel.self) private var model
    @Environment(\.lifecycle) private var lifecycle
    @Environment(\.isInDemoMode) private var isInDemoMode
    @Environment(\.demoExitPresentation) private var demoExitPresentation

    init(
        report: YearReportModel,
        recordingWarning: RecordingConfigurationWarningModel? = nil,
        navigation: SceneNavigationModel.Settings? = nil,
    ) {
        self.report = report
        self
            .recordingWarning = recordingWarning ??
            RecordingConfigurationWarningModel(preferences: report.preferences)
        _navigation = State(initialValue: navigation ?? SceneNavigationModel.Settings())
    }

    private var searchQuery: String {
        navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        @Bindable var navigation = navigation
        List(selection: $navigation.selectedRoute) {
            if isSearching {
                ForEach(searchResults) { result in
                    searchNavigationRow(result)
                }
            } else {
                if recordingWarning.isPresented {
                    recordingWarningSection
                }
                if isInDemoMode, demoExitPresentation == .session {
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
        .searchable(
            text: $navigation.searchText,
            prompt: String(localized: .settingsSearchPrompt),
        )
        .overlay {
            if isSearching, searchResults.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
    }

    private var recordingWarningSection: some View {
        Section {
            NavigationLink(value: SettingsRoute(.devices)) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(.settingsRecordingWarningTitle)
                            .font(.headline)
                        Text(.settingsRecordingWarningMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemSymbol: .exclamationmarkTriangleFill)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
            }
            Button(.settingsRecordingWarningDismiss, role: .cancel) {
                recordingWarning.dismiss()
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
                navigation.showRegions = true
            case .placesYear, .recording, .privacyBackups, .attachments, .loggedDays, .devices,
                 .alerts, .appearance, .year, .siri,
                 .widgets, .shareEvidence, .estimatedTime, .insightsAccuracy, .personalization,
                 .data, .privacyDiagnostics, .about:
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
            case .placesYear, .recording, .privacyBackups, .attachments, .loggedDays, .regions,
                 .alerts, .appearance, .siri, .widgets,
                 .shareEvidence, .estimatedTime, .insightsAccuracy, .personalization, .data,
                 .privacyDiagnostics, .about:
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
}

#if DEBUG
    #Preview { SettingsView.snapshotPreviews }
#endif
