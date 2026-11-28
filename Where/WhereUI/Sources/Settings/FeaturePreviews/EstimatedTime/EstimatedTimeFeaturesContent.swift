import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Keeps the large concrete `Form` type behind a small nominal view so the
/// focus scope does not copy the form's full value onto the stack while a
/// navigation push is preparing its destination.
struct EstimatedTimeFeaturesContent: View {
    @State private var showingPlanner = false
    let report: YearReportModel

    var body: some View {
        Form {
            FeatureMarketingHeaderRow(
                title: String(localized: .settingsExploreEstimatedTimeTitle),
                tagline: .settingsExploreEstimatedTimeTagline,
                destination: .estimatedTime,
            )

            if !report.showsEstimatedTimeAndPlanning {
                Section {
                    FeatureEstimatedTimeStatusPreview(state: .disabled)
                        .featureMarketingRow(order: 1)
                }
            }

            EstimatedTimeOverviewSection(report: report)

            EstimatedTimePaceSection()

            EstimatedTimeCalculationSection(isEnabled: report.showsEstimatedTimeAndPlanning)

            EstimatedTimeTotalsSection()

            EstimatedTimeSurfacesSection(report: report, showPlanner: { showingPlanner = true })
        }
        .whereFormRoot()
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
        .sheet(isPresented: $showingPlanner) { PlannedStaysView(report: report) }
    }
}

private struct EstimatedTimeForecastPreview: View {
    let report: YearReportModel

    var body: some View {
        if forecasts.isEmpty {
            FeatureEstimatedTimeStatusPreview(state: .unavailable)
        } else {
            LocationForecastPanel(
                forecasts: forecasts,
                microprintRegions: report.ranking.primary.map(\.region),
                homeRegion: report.forecasts.planning.homeRegion,
            )
            .saturation(report.showsEstimatedTimeAndPlanning ? 1 : 0)
        }
    }

    private var forecasts: [LocationForecast] {
        report.primaryRegionForecasts
    }
}

private struct EstimatedTimeExplanation: View {
    let title: String
    let detail: String
    let systemSymbol: SFSymbol

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                Label(title, systemSymbol: systemSymbol)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EstimatedTimeOverviewSection: View {
    let report: YearReportModel

    var body: some View {
        Section {
            EstimatedTimeForecastPreview(report: report)
                .featureMarketingRow(order: 1)
                .settingsRow(EstimatedTimeFeaturesView.Item.overview, restingBackground: .clear)
        }
    }
}

private struct EstimatedTimePaceSection: View {
    var body: some View {
        Section {
            EstimatedTimeExplanation(
                title: String(localized: .settingsExploreEstimatedTimePaceTitle),
                detail: String(localized: .settingsExploreEstimatedTimePaceDescription),
                systemSymbol: .chartLineUptrendXyaxis,
            )
            .featureMarketingRow(order: 2)
            .settingsRow(EstimatedTimeFeaturesView.Item.pace, restingBackground: .clear)

            EstimatedTimeExplanation(
                title: String(localized: .settingsExploreEstimatedTimePlanTitle),
                detail: String(localized: .settingsExploreEstimatedTimePlanDescription),
                systemSymbol: .calendarBadgeClock,
            )
            .featureMarketingRow(order: 3)
            .settingsRow(EstimatedTimeFeaturesView.Item.planning, restingBackground: .clear)
        }
    }
}

private struct EstimatedTimeCalculationSection: View {
    let isEnabled: Bool

    var body: some View {
        Section {
            FeatureEstimatedTimeCalculationExample()
                .saturation(isEnabled ? 1 : 0)
                .featureMarketingRow(order: 4)
                .settingsRow(
                    EstimatedTimeFeaturesView.Item.calculation,
                    restingBackground: .clear,
                )
        }
    }
}

private struct EstimatedTimeTotalsSection: View {
    var body: some View {
        Section {
            EstimatedTimeExplanation(
                title: String(localized: .settingsExploreEstimatedTimeTotalsTitle),
                detail: String(localized: .settingsExploreEstimatedTimeTotalsDescription),
                systemSymbol: .airplane,
            )
            .featureMarketingRow(order: 5)
            .settingsRow(EstimatedTimeFeaturesView.Item.totals, restingBackground: .clear)
        }
    }
}

#if DEBUG
    #Preview { NavigationStack { EstimatedTimeFeaturesView.snapshotPreviews }.whereBroadwayRoot() }
#endif

/// A concrete, fixed-year example that makes the forecast's three inputs and
/// arithmetic visible without fabricating a forecast from the user's data.
private struct FeatureEstimatedTimeCalculationExample: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.spacing.large) {
                Text(String(localized: .settingsExploreEstimatedTimeCalculationTitle))
                    .font(.headline)

                Text(String(localized: .settingsExploreEstimatedTimeCalculationIntro))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                EstimatedTimeCalculationTimeline()

                EstimatedTimeCalculationLegend()

                Divider()

                EstimatedTimeCalculationResult()

                Text(String(localized: .settingsExploreEstimatedTimeCalculationOtherRegions))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct EstimatedTimeCalculationLegend: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            EstimatedTimeLegendItem(
                title: .settingsExploreEstimatedTimeCalculationElapsed,
                color: Color.secondary.opacity(0.35),
            )
            EstimatedTimeLegendItem(
                title: .settingsExploreEstimatedTimeCalculationPlanned,
                color: .blue,
            )
            EstimatedTimeLegendItem(
                title: .settingsExploreEstimatedTimeCalculationRemaining,
                color: .blue.opacity(0.24),
            )
        }
        .font(.footnote)
    }
}

private struct EstimatedTimeLegendItem: View {
    let title: LocalizedStringResource
    let color: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let size = stylesheet.featureDiscovery.estimatedTime.legendDotSize
        Label {
            Text(String(localized: title))
        } icon: {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}

private struct EstimatedTimeCalculationResult: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: stylesheet.featureDiscovery.estimatedTime.calculationSpacing,
        ) {
            Text(String(localized: .settingsExploreEstimatedTimeCalculationPace))
            Text(String(localized: .settingsExploreEstimatedTimeCalculationProjection))
            Text(String(localized: .settingsExploreEstimatedTimeCalculationResult))
                .bold()
        }
        .font(.subheadline)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
    #Preview("Calculation") {
        FeatureEstimatedTimeCalculationExample()
            .padding()
            .whereBroadwayRoot()
    }
#endif

/// Educational fallback when a live estimated-time panel cannot render.
private struct FeatureEstimatedTimeStatusPreview: View {
    enum State {
        case disabled
        case unavailable
    }

    let state: State

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemSymbol: .chartLineUptrendXyaxis)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch state {
            case .disabled:
                String(localized: .settingsExploreEstimatedTimeDisabledTitle)
            case .unavailable:
                String(localized: .settingsExploreEstimatedTimeUnavailableTitle)
        }
    }

    private var message: String {
        switch state {
            case .disabled:
                String(localized: .settingsExploreEstimatedTimeDisabledDescription)
            case .unavailable:
                String(localized: .settingsExploreEstimatedTimeUnavailableDescription)
        }
    }
}

#if DEBUG
    #Preview("Unavailable status") {
        FeatureEstimatedTimeStatusPreview(state: .unavailable)
            .padding()
            .whereBroadwayRoot()
    }
#endif
