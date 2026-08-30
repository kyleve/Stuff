import SwiftUI
import WhereCore

/// Places a region and its estimate inline when both remain readable.
struct LocationForecastEstimateLabel: View {
    let forecast: LocationForecast
    let tint: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let row = stylesheet.locationForecast.row

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: row.estimateSpacing) {
                regionLabel
                estimateLabel
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: row.contentSpacing) {
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
        if let forecast = report.forecasts.leadingForecasts(report: report.report).first {
            LocationForecastEstimateLabel(forecast: forecast, tint: .blue)
                .padding()
                .whereBroadwayRoot()
        }
    }
#endif
