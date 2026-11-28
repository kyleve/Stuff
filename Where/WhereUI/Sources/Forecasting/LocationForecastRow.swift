import RegionKit
import SwiftUI
import WhereCore

/// One region's annual projection rendered as a tinted visa endorsement.
struct LocationForecastRow: View {
    let forecast: LocationForecast
    var homeRegion: Region?

    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        let row = style.row
        let tint = regionStyles.style(for: forecast.region).tint
        let shape = RoundedRectangle(cornerRadius: row.cornerRadius)

        VStack(alignment: .leading, spacing: row.contentSpacing) {
            LocationForecastEstimateLabel(forecast: forecast, tint: tint)

            Text(WhereFormat.forecastPercentage(forecast.estimatedTotalDays, year: forecast.year))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LocationForecastProgress(forecast: forecast, tint: tint)

            ForecastBasisLabels(forecast: forecast, gapDescription: gapDescription, row: row)
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

    private var gapDescription: String {
        if homeRegion == forecast.region {
            return String(localized: .forecastHomeContribution(WhereFormat
                    .dayCount(forecast.projectedRemainingDays)))
        }
        return String(localized: .forecastPatternContribution(WhereFormat
                .dayCount(forecast.projectedRemainingDays)))
    }

    private var accessibilitySummary: String {
        var parts = [
            String(WhereFormat.locationForecastEstimate(
                region: forecast.region,
                days: forecast.estimatedTotalDays,
            ).characters),
            WhereFormat.locationForecastBasis(yearToDateDays: forecast.yearToDateDays),
        ]
        parts.append(WhereFormat.forecastPercentage(
            forecast.estimatedTotalDays,
            year: forecast.year,
        ))
        if forecast.plannedDays.upper > 0 {
            parts
                .append(String(localized: .forecastPlannedContribution(WhereFormat
                        .dayCount(forecast.plannedDays))))
        }
        if forecast.projectedRemainingDays.upper > 0 {
            parts.append(gapDescription)
        }
        return parts.joined(separator: " ")
    }
}

private struct ForecastBasisLabels: View {
    let forecast: LocationForecast
    let gapDescription: String
    let row: WhereStylesheet.LocationForecastStyle.Row

    var body: some View {
        VStack(alignment: .leading, spacing: row.estimateSpacing) {
            Text(WhereFormat.locationForecastBasis(
                yearToDateDays: forecast.yearToDateDays,
            ))
            .font(row.detailFont)
            .foregroundStyle(.secondary)

            if forecast.plannedDays.upper > 0 {
                Text(String(localized: .forecastPlannedContribution(WhereFormat
                        .dayCount(forecast.plannedDays))))
                    .font(row.detailFont)
                    .foregroundStyle(.secondary)
            }
            if forecast.projectedRemainingDays.upper > 0 {
                Text(gapDescription)
                    .font(row.detailFont)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        if let forecast = report.primaryRegionForecasts.first {
            LocationForecastRow(
                forecast: forecast,
                homeRegion: report.forecasts.planning.homeRegion,
            )
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif

/// Places a region and its estimate inline when both remain readable.
struct LocationForecastEstimateLabel: View {
    let forecast: LocationForecast
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let row = stylesheet.locationForecast.row

        if row.layout == .stacked {
            VStack(alignment: .leading, spacing: row.estimateSpacing) {
                regionLabel
                estimateLabel
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: row.contentSpacing) {
                    regionLabel
                    estimateLabel
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: row.estimateSpacing) {
                    regionLabel
                    estimateLabel
                }
            }
        }
    }

    private var regionLabel: some View {
        Text(forecast.region.localizedName)
            .font(stylesheet.locationForecast.row.regionFont)
            .bold()
            .foregroundStyle(tint)
    }

    private var estimateLabel: some View {
        Text(WhereFormat.dayCount(forecast.estimatedTotalDays))
            .font(stylesheet.locationForecast.row.estimateFont)
            .bold()
            .monospacedDigit()
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        if let forecast = report.primaryRegionForecasts.first {
            LocationForecastEstimateLabel(forecast: forecast, tint: .blue)
                .padding()
                .whereBroadwayRoot()
        }
    }
#endif
