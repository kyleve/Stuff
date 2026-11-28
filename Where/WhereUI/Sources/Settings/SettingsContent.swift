import InstallerKit
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
    @State private var navigation: SettingsView.Navigation
    @Environment(UpdateModel.self) private var updates: UpdateModel?
    @Environment(WhereSession.self) private var session
    @Environment(WhereModel.self) private var model
    @Environment(\.lifecycle) private var lifecycle
    @Environment(\.isInDemoMode) private var isInDemoMode
    @Environment(\.demoExitPresentation) private var demoExitPresentation

    init(
        report: YearReportModel,
        recordingWarning: RecordingConfigurationWarningModel? = nil,
        navigation: SettingsView.Navigation? = nil,
    ) {
        self.report = report
        self
            .recordingWarning = recordingWarning ??
            RecordingConfigurationWarningModel(preferences: report.preferences)
        _navigation = State(initialValue: navigation ?? SettingsView.Navigation())
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
        destination.isAvailable(isInDemoMode: isInDemoMode, updatesEnabled: updates != nil)
    }

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: $navigation.selectedRoute) {
            if isSearching {
                ForEach(searchResults) { result in
                    SettingsRouteRow(route: SettingsRoute(result), present: present) {
                        SettingsSearchLabel(result: result)
                    }
                }
            } else {
                if recordingWarning.isPresented {
                    SettingsRecordingWarningSection(dismiss: recordingWarning.dismiss)
                }
                if isInDemoMode, demoExitPresentation == .session {
                    SettingsDemoSection(exit: exitDemoMode)
                }
                ForEach(SettingsListSection.allCases, id: \.self) { section in
                    let destinations = section.destinations.filter(isAvailable)
                    if !destinations.isEmpty {
                        SettingsGroupSection(
                            section: section,
                            destinations: destinations,
                            subtitle: subtitle(for:),
                            present: present,
                        )
                    }
                }
            }
        }
        .whereFormRoot()
        .navigationTitle(String(localized: .settingsTitle))
        .searchable(
            text: $navigation.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: String(localized: .settingsSearchPrompt),
        )
        .overlay {
            if isSearching, searchResults.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
    }

    /// Tear the demo world down and re-drive the launch, through the same
    /// `LifecycleProxy` the reset flow uses. The relaunch parks on the
    /// onboarding gate (or resolves straight through for someone who had
    /// already onboarded before trying the demo).
    private func exitDemoMode() {
        Task { await lifecycle.teardown(WhereLaunch.exitDemoPlan(for: model), input: session) }
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
                 .data, .privacyDiagnostics, .updates, .about:
                assertionFailure("\(destination) is a push destination, not a sheet")
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
            case .updates: updates?.attentionTitle
            case .year:
                report.selectedYear.formatted(.number.grouping(.never))
            case .placesYear, .recording, .privacyBackups, .attachments, .loggedDays, .regions,
                 .alerts, .appearance, .siri, .widgets,
                 .shareEvidence, .estimatedTime, .insightsAccuracy, .personalization, .data,
                 .privacyDiagnostics, .about:
                nil
        }
    }
}

private struct SettingsRecordingWarningSection: View {
    let dismiss: () -> Void

    var body: some View {
        Section {
            RecordingWarningLink()
            Button(.settingsRecordingWarningDismiss, role: .cancel) {
                dismiss()
            }
        }
    }
}

private struct RecordingWarningLink: View {
    var body: some View {
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
    }
}

/// The way out of demo mode, at the very top of the list where a temporary
/// state belongs — above the real settings rather than filed among them.
///
/// No confirmation: there is nothing to lose. Demo data was never saved,
/// and leaving is exactly what quitting the app would do anyway, so a
/// "are you sure?" would overstate the stakes.
private struct SettingsDemoSection: View {
    let exit: () -> Void

    var body: some View {
        Section {
            ExitDemoButton(exit: exit)
        } header: {
            Text(String(localized: .settingsDemoHeader))
        } footer: {
            Text(String(localized: .settingsDemoFooter))
        }
    }
}

private struct ExitDemoButton: View {
    let exit: () -> Void

    var body: some View {
        Button {
            exit()
        } label: {
            Label(
                String(localized: .settingsDemoExit),
                systemSymbol: .rectanglePortraitAndArrowRight,
            )
        }
    }
}

/// A top-level drill-in row: icon + group title, with a value subtitle where
/// one is cheap and useful (location status, the report year).
private struct SettingsGroupLabel: View {
    let destination: SettingsDestination
    let subtitle: String?

    var body: some View {
        LabeledContent {
            if let subtitle {
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
}

/// A search result row: the owning group's icon beside the setting's name
/// over its parent group, so a result reads as belonging to its section.
private struct SettingsSearchLabel: View {
    let result: SettingsSearchResult

    var body: some View {
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

private struct SettingsRouteRow<Content: View>: View {
    let route: SettingsRoute
    let present: (SettingsDestination) -> Void
    @ViewBuilder let label: Content

    var body: some View {
        if route.destination.isSheet {
            Button { present(route.destination) } label: { label }
                .tint(.primary)
        } else {
            NavigationLink(value: route) { label }
        }
    }
}

private struct SettingsGroupSection: View {
    let section: SettingsListSection
    let destinations: [SettingsDestination]
    let subtitle: (SettingsDestination) -> String?
    let present: (SettingsDestination) -> Void

    var body: some View {
        Section {
            ForEach(destinations, id: \.self) { destination in
                SettingsRouteRow(route: SettingsRoute(destination), present: present) {
                    SettingsGroupLabel(destination: destination, subtitle: subtitle(destination))
                }
            }
        } header: {
            if let headerTitle = section.headerTitle {
                Text(headerTitle)
            }
        }
    }
}

#if DEBUG
    #Preview { SettingsView.snapshotPreviews }
#endif

/// The colored rounded-square icon chip for a top-level settings row (iOS-Settings
/// style): an SF Symbol centered on a per-section color. The glyph is white in
/// light mode and black in dark mode; the chip geometry comes from
/// `WhereStylesheet.SettingsStyle`.
private struct SettingsIcon: View {
    let systemSymbol: SFSymbol
    let color: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let settings = stylesheet.settings
        Image(systemSymbol: systemSymbol)
            .font(.system(size: settings.iconSymbolSize, weight: .semibold))
            .foregroundStyle(settings.iconForeground)
            .frame(width: settings.iconSize, height: settings.iconSize)
            .background(
                color,
                in: RoundedRectangle(cornerRadius: settings.iconCornerRadius, style: .continuous),
            )
            // Decorative: the row's text carries the accessibility label.
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Settings icons") { SettingsIconPreview() }

    private struct SettingsIconPreview: View {
        var body: some View {
            List {
                ForEach(SettingsDestination.allCases, id: \.self) { destination in
                    Label {
                        Text(destination.rowTitle)
                    } icon: {
                        SettingsIcon(
                            systemSymbol: destination.systemSymbol,
                            color: destination.iconColor,
                        )
                    }
                }
            }
            .whereBroadwayRoot()
        }
    }
#endif
