#if DEBUG
    @_spi(Testing) import InstallerKitUI
#endif
import BroadwayUI
import InstallerKit
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Settings tab: an iOS-Settings-style top-level list of icon rows that drill
/// into grouped sub-screens — App Updates for eligible builds, then Data (attachments, logged days,
/// regions), then devices, alerts, appearance, report year, data management,
/// feature discovery, and About — plus a search field that filters individual settings and
/// deep-links to the screen — and the row — containing each.
///
/// The top level owns nothing but navigation; behavior lives in the sub-screens
/// (`DevicesSettingsView`, `AlertsSettingsView`, …). The scene injects its report.
/// This view owns the backup and reminders models above the adaptive container;
/// the `WhereSession` coordinator (recording/location) and
/// `WhereModel` (reset) come from the environment via the sub-screens.
struct SettingsView: View {
    let report: YearReportModel
    let recordingWarning: RecordingConfigurationWarningModel
    @State private var backup: BackupModel
    @State private var reminders: RemindersSettingsModel
    @State private var navigation: SceneNavigationModel.Settings

    @Environment(\.stylesheet) private var stylesheet

    init(
        report: YearReportModel,
        recordingWarning: RecordingConfigurationWarningModel? = nil,
        navigation: SceneNavigationModel.Settings? = nil,
    ) {
        _navigation = State(initialValue: navigation ?? SceneNavigationModel.Settings())
        self.report = report
        self.recordingWarning = recordingWarning ?? RecordingConfigurationWarningModel(
            preferences: report.preferences,
        )
        _backup = State(initialValue: BackupModel(services: report.services))
        _reminders = State(initialValue: RemindersSettingsModel(
            services: report.services,
            preferences: report.preferences,
            now: report.now,
        ))
    }

    var body: some View {
        @Bindable var navigation = navigation
        AdaptiveHistoryContainer { arrangement in
            NavigationSplitView(
                columnVisibility: .constant(.all),
                preferredCompactColumn: $navigation.compactColumn,
            ) {
                SettingsContent(
                    report: report,
                    recordingWarning: recordingWarning,
                    navigation: navigation,
                )
                .navigationSplitViewColumnWidth(
                    min: stylesheet.adaptiveHistory.minimumControlsWidth,
                    ideal: stylesheet.adaptiveHistory.minimumHistoryWidth,
                )
            } detail: {
                NavigationStack(path: $navigation.path) {
                    Group {
                        if let route = navigation.selectedRoute {
                            destination(for: route)
                        } else {
                            ContentUnavailableView(
                                String(localized: .settingsTitle),
                                systemSymbol: .gearshape,
                            )
                        }
                    }
                    .navigationDestination(for: SettingsRoute.self) { route in
                        destination(for: route)
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: stylesheet.adaptiveHistory.minimumHistoryWidth,
                    ideal: stylesheet.adaptiveHistory.minimumHistoryWidth,
                )
            }
            .navigationSplitViewStyle(.balanced)
            .environment(\.horizontalSizeClass, arrangement == .compact ? .compact : .regular)
            .bHorizontalSizeClass(arrangement == .compact ? .compact : .regular)
        }
        .sheet(isPresented: $navigation.showRegions) {
            RegionsSettingsView(usedThisYear: regionsUsedThisYear)
        }
    }

    private func destination(for route: SettingsRoute) -> some View {
        SettingsDestinationView(route: route, report: report, backup: backup, reminders: reminders)
    }

    /// Regions with days in the selected report year, so the region editor can
    /// surface a "used this year" group (grouping order only — it doesn't affect
    /// what's saved). `.other` isn't a pickable region, so it's dropped.
    private var regionsUsedThisYear: Set<Region> {
        guard let totals = report.report?.totals else { return [] }
        return Set(totals.filter { $0.key != .other && $0.value > 0 }.map(\.key))
    }
}

/// The shared typed destination builder for both adaptive navigation and standalone panes.
private struct SettingsDestinationView: View {
    let route: SettingsRoute
    let report: YearReportModel
    let backup: BackupModel
    let reminders: RemindersSettingsModel
    @Environment(UpdateModel.self) private var updates: UpdateModel?
    @Environment(\.isInDemoMode) private var isInDemoMode
    @Environment(WhereSession.self) private var session
    @Environment(WhereModel.self) private var model
    @Environment(\.primaryAppIconName) private var primaryAppIconName

    var body: some View {
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
            case .placesYear:
                PlacesYearFeaturesView(report: report, focus: route.focus)
            case .recording:
                RecordingFeaturesView(
                    authorizationStatus: session.authorizationStatus,
                    isTracking: session.isTracking,
                    focus: route.focus,
                )
            case .privacyBackups:
                PrivacyBackupsFeaturesView(
                    configuration: model.diagnosticReporting.effectiveConfiguration,
                    focus: route.focus,
                )
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
            case .estimatedTime:
                EstimatedTimeFeaturesView(report: report, focus: route.focus)
            case .insightsAccuracy:
                InsightsAccuracyFeaturesView(
                    report: report,
                    focus: route.focus,
                )
            case .personalization:
                PersonalizationFeaturesView(
                    report: report,
                    focus: route.focus,
                    primaryAppIconName: primaryAppIconName,
                )
            case .data:
                DataSettingsView(report: report, backup: backup, focus: route.focus)
            case .privacyDiagnostics:
                PrivacyDiagnosticsSettingsView(focus: route.focus)
            case .updates:
                if let updates, !isInDemoMode {
                    DevelopmentUpdatesView(model: updates, focus: route.focus)
                }
            case .about:
                AboutSettingsView(
                    focus: route.focus,
                    diagnosticReportingConfiguration: model.diagnosticReporting
                        .effectiveConfiguration,
                )
        }
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
                name: "BrowseColumn",
                configurations: [SnapshotConfiguration(device: AdaptiveHistorySnapshotFixture
                        .browseColumn)],
            ) {
                snapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
            }
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenRepresentative + [
                    SnapshotConfiguration(
                        layoutDirection: .rightToLeft,
                        device: .iPhoneFullContent,
                    ),
                ],
                measurementReadiness: .immediate,
            ) {
                snapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
            }
            whereSnapshot(
                name: "UpdateAvailable",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                SettingsView(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(InstallerPreview.model(.available))
            }
            whereSnapshot(
                name: "LocalBuild",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                SettingsView(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(InstallerPreview.model(.local))
            }
            // Demo mode: the exit section on top, and the groups that would
            // reach past the demo (backup, erase/reset, app icon) gone.
            whereSnapshot(
                name: "DemoMode",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                snapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(\.isInDemoMode, true)
            }
            whereSnapshot(
                name: "RecordingConfigurationWarning",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                snapshotList(
                    report: PreviewSupport.loadedYearReportModel(),
                    recordingWarning: PreviewSupport.recordingConfigurationWarningModel(),
                )
                .environment(PreviewSupport.loadedModel())
                .environment(PreviewSupport.loadedSession())
            }
        }

        private static func snapshotList(
            report: YearReportModel,
            recordingWarning: RecordingConfigurationWarningModel? = nil,
        ) -> some View {
            let backup = BackupModel(services: report.services)
            let reminders = RemindersSettingsModel(
                services: report.services,
                preferences: report.preferences,
                now: report.now,
            )
            return NavigationStack {
                SettingsContent(report: report, recordingWarning: recordingWarning)
                    .navigationDestination(for: SettingsRoute.self) { route in
                        SettingsDestinationView(
                            route: route,
                            report: report,
                            backup: backup,
                            reminders: reminders,
                        )
                    }
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
                .push(to: PlacesYearFeaturesView.flyoverID),
                .push(to: RecordingFeaturesView.flyoverID),
                .push(to: PrivacyBackupsFeaturesView.flyoverID),
                .push(to: SiriFeaturesView.flyoverID),
                .push(to: WidgetFeaturesView.flyoverID),
                .push(to: ShareEvidenceFeaturesView.flyoverID),
                .push(to: EstimatedTimeFeaturesView.flyoverID),
                .push(to: InsightsAccuracyFeaturesView.flyoverID),
                .push(to: PersonalizationFeaturesView.flyoverID),
                .push(to: DataSettingsView.flyoverID),
                .push(to: PrivacyDiagnosticsSettingsView.flyoverID),
                .push(to: DevelopmentUpdatesView.flyoverID),
                .push(to: AboutSettingsView.flyoverID),
            ],
        ) { world in
            SettingsView(report: world.report)
        }
    }
#endif
