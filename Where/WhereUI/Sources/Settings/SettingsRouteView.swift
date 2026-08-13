import SwiftUI

/// Builds one pushed Settings destination from the root's typed route and
/// view-scoped collaborators. Keeping route rendering in a nominal child lets
/// tests exercise the same destination tree without a test-only Settings API.
struct SettingsRouteView: View {
    let route: SettingsRoute
    let report: YearReportModel
    let backup: BackupModel
    let reminders: RemindersSettingsModel

    @Environment(WhereSession.self) private var session

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
                PersonalizationFeaturesView(report: report, focus: route.focus)
            case .data:
                DataSettingsView(report: report, backup: backup, focus: route.focus)
            case .about:
                AboutSettingsView(focus: route.focus)
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
