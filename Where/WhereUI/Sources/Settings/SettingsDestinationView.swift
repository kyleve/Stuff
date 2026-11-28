import InstallerKit
import SwiftUI
import WhereCore

/// The shared typed destination builder for both adaptive navigation and standalone panes.
struct SettingsDestinationView: View {
    let route: SettingsRoute
    let report: YearReportModel
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
                AlertsSettingsDestination(report: report, session: session, focus: route.focus)
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
                DataSettingsDestination(report: report, focus: route.focus)
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
    #Preview { SettingsDestinationPreview() }

    private struct SettingsDestinationPreview: View {
        var body: some View {
            NavigationStack {
                SettingsDestinationView(
                    route: SettingsRoute(.about),
                    report: PreviewSupport.loadedYearReportModel(),
                )
            }
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
            .whereBroadwayRoot()
        }
    }
#endif
