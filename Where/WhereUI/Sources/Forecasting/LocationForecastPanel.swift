import RegionKit
import SwiftUI
import WhereCore

/// Annual location estimates shared by the Locations summary and a focused
/// region calendar. An optional edit action belongs only to the current region.
struct LocationForecastPanel: View {
    let forecasts: [LocationForecast]
    var plannedStay: PlannedStay?
    var editableRegion: Region?
    var editAction: (() -> Void)?

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.LocationForecastStyle {
        stylesheet.locationForecast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            if let elapsedDays = forecasts.first?.elapsedDays {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .accessibilityHidden(true)
                        Text(String(localized: .locationForecastTitle))
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: stylesheet.spacing.large)
                        Text(WhereFormat.locationForecastElapsed(days: elapsedDays))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: style.estimateSpacing) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .accessibilityHidden(true)
                            Text(String(localized: .locationForecastTitle))
                        }
                        Text(WhereFormat.locationForecastElapsed(days: elapsedDays))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .font(.headline)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .accessibilityHidden(true)
                    Text(String(localized: .locationForecastTitle))
                }
                .font(.headline)
            }

            ForEach(forecasts, id: \.region) { forecast in
                LocationForecastRow(
                    forecast: forecast,
                    plannedStay: plannedStay,
                )
            }

            if editableRegion != nil, let editAction {
                Button(
                    String(localized: .locationForecastEditStay),
                    systemImage: "calendar.badge.clock",
                    action: editAction,
                )
                .buttonStyle(.bordered)
            }
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: style.cornerRadius),
            )
        }
    }
}

private struct LocationForecastRow: View {
    let forecast: LocationForecast
    var plannedStay: PlannedStay?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.locationForecast.estimateSpacing) {
            Text(WhereFormat.locationForecastEstimate(
                region: forecast.region,
                days: forecast.estimatedTotalDays,
            ))
            .font(.subheadline)
            Text(WhereFormat.locationForecastBasis(
                yearToDateDays: forecast.yearToDateDays,
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let plannedStay, plannedStay.region == forecast.region {
                Text(WhereFormat.locationForecastPlan(through: plannedStay.through))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        LocationForecastPanel(
            forecasts: report.forecasts.leadingForecasts(report: report.report),
            plannedStay: report.forecasts.activePlannedStay,
            editableRegion: .newYork,
            editAction: {},
        )
        .padding()
    }
#endif
