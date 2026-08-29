import SwiftUI
import WhereCore

/// One region's annual projection rendered as a tinted visa endorsement.
struct LocationForecastRow: View {
    let forecast: LocationForecast
    var plannedStay: PlannedStay?

    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        let row = style.row
        let tint = regionStyles.style(for: forecast.region).tint
        let shape = RoundedRectangle(cornerRadius: row.cornerRadius)

        VStack(alignment: .leading, spacing: row.contentSpacing) {
            VStack(alignment: .leading, spacing: row.estimateSpacing) {
                Text(forecast.region.localizedName)
                    .font(row.regionFont)
                    .bold()
                    .foregroundStyle(tint)
                Text(WhereFormat.dayCount(forecast.estimatedTotalDays))
                    .font(row.estimateFont)
                    .bold()
                    .monospacedDigit()
            }

            LocationForecastProgress(forecast: forecast, tint: tint)

            VStack(alignment: .leading, spacing: row.estimateSpacing) {
                Text(WhereFormat.locationForecastBasis(
                    yearToDateDays: forecast.yearToDateDays,
                ))
                .font(row.detailFont)
                .foregroundStyle(.secondary)

                if let plannedStay, plannedStay.region == forecast.region {
                    Text(WhereFormat.locationForecastPlan(through: plannedStay.through))
                        .font(row.detailFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(row.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(tint.opacity(style.ink.rowFillOpacity))
        }
        .overlay {
            shape.strokeBorder(
                tint.opacity(style.ink.rowOutlineOpacity),
                lineWidth: row.outlineWidth,
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [
            String(WhereFormat.locationForecastEstimate(
                region: forecast.region,
                days: forecast.estimatedTotalDays,
            ).characters),
            WhereFormat.locationForecastBasis(yearToDateDays: forecast.yearToDateDays),
        ]
        if let plannedStay, plannedStay.region == forecast.region {
            parts.append(WhereFormat.locationForecastPlan(through: plannedStay.through))
        }
        return parts.joined(separator: " ")
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        if let forecast = report.forecasts.leadingForecasts(report: report.report).first {
            LocationForecastRow(
                forecast: forecast,
                plannedStay: report.forecasts.activePlannedStay,
            )
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif
