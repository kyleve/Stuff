import BroadwayUI
import InstallerKit
import Observation
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore
#if DEBUG
    @_spi(Testing) import InstallerKitUI
#endif

/// Settings tab: an iOS-Settings-style top-level list of icon rows that drill
/// into grouped sub-screens — App Updates for eligible builds, then Data (attachments, logged days,
/// regions), then devices, alerts, appearance, report year, data management,
/// feature discovery, and About — plus a search field that filters individual settings and
/// deep-links to the screen — and the row — containing each.
///
/// The top level owns nothing but navigation; behavior lives in the sub-screens
/// (`DevicesSettingsView`, `AlertsSettingsView`, …). The scene injects its report.
/// Each destination owns its editing state. Sub-screens get the session and
/// app coordinators from the environment.
struct SettingsView: View {
    @MainActor @Observable
    final class Navigation {
        // Settings, evidence, and feature-gallery routes share the same stack.
        // NavigationPath retains each value's concrete Hashable identity.
        var path = NavigationPath()
        private var route: SettingsRoute?
        var compactColumn = NavigationSplitViewColumn.sidebar
        var selectedRoute: SettingsRoute? {
            get { route }
            set {
                guard route != newValue else { return }
                route = newValue
                path = NavigationPath()
                if newValue != nil {
                    compactColumn = .detail
                }
            }
        }

        var searchText = ""
        var showRegions = false
    }

    let report: YearReportModel
    let recordingWarning: RecordingConfigurationWarningModel
    @State private var navigation: SettingsView.Navigation

    @Environment(\.stylesheet) private var stylesheet

    init(
        report: YearReportModel,
        recordingWarning: RecordingConfigurationWarningModel? = nil,
        navigation: SettingsView.Navigation? = nil,
        initialRoute: SettingsRoute? = nil,
    ) {
        let navigation = navigation ?? SettingsView.Navigation()
        if let initialRoute {
            navigation.selectedRoute = initialRoute
        }
        _navigation = State(initialValue: navigation)
        self.report = report
        self.recordingWarning = recordingWarning ?? RecordingConfigurationWarningModel(
            preferences: report.preferences,
        )
    }

    var body: some View {
        @Bindable var navigation = navigation
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
                min: stylesheet.adaptivePane.minimumControlsWidth,
                ideal: stylesheet.adaptivePane.minimumDetailWidth,
            )
        } detail: {
            SettingsDetailColumn(
                navigation: navigation,
                report: report,
                minimumWidth: stylesheet.adaptivePane.minimumDetailWidth,
            )
        }
        .navigationSplitViewStyle(.balanced)
        .environment(
            \.horizontalSizeClass,
            stylesheet.adaptivePane.panes == .single ? .compact : .regular,
        )
        .bHorizontalSizeClass(stylesheet.adaptivePane.panes == .single ? .compact : .regular)
        .background(.background)
        .sheet(isPresented: $navigation.showRegions) {
            RegionsSettingsView(usedThisYear: regionsUsedThisYear)
                .whereScreenBoundary()
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

private struct SettingsDetailColumn: View {
    @Bindable var navigation: SettingsView.Navigation
    let report: YearReportModel
    let minimumWidth: CGFloat

    var body: some View {
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
            min: minimumWidth,
            ideal: minimumWidth,
        )
    }

    private func destination(for route: SettingsRoute) -> some View {
        SettingsDestinationView(route: route, report: report)
            .whereScreenBoundary()
    }
}

#if DEBUG
    extension SettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "BrowseColumn",
                configurations: [SnapshotConfiguration(device: DuoLayoutSnapshotFixture
                        .browseColumn)],
            ) {
                SettingsSnapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
            }
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                    SnapshotConfiguration(device: .iPadFullContent, snapshotType: .accessibility),
                ],
            ) {
                SettingsSnapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
            }
            whereSnapshot(
                name: "UpdateAvailable",
                configurations: .fullContentPhoneLightDark,
            ) {
                SettingsSnapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(InstallerPreview.model(.available))
            }
            whereSnapshot(
                name: "LocalBuild",
                configurations: .fullContentPhoneLightDark,
            ) {
                SettingsSnapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(InstallerPreview.model(.local))
            }
            // Demo mode: the exit section on top, and the groups that would
            // reach past the demo (backup, erase/reset, app icon) gone.
            whereSnapshot(
                name: "DemoMode",
                configurations: .fullContentPhoneLightDark,
            ) {
                SettingsSnapshotList(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(\.isInDemoMode, true)
            }
            whereSnapshot(
                name: "RecordingConfigurationWarning",
                configurations: .fullContentPhoneLightDark,
            ) {
                SettingsSnapshotList(
                    report: PreviewSupport.loadedYearReportModel(),
                    recordingWarning: PreviewSupport.recordingConfigurationWarningModel(),
                )
                .environment(PreviewSupport.loadedModel())
                .environment(PreviewSupport.loadedSession())
            }
        }
    }

    private struct SettingsSnapshotList: View {
        let report: YearReportModel
        var recordingWarning: RecordingConfigurationWarningModel?

        var body: some View {
            NavigationStack {
                SettingsContent(report: report, recordingWarning: recordingWarning)
                    .navigationDestination(for: SettingsRoute.self) { route in
                        SettingsDestinationView(route: route, report: report)
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
