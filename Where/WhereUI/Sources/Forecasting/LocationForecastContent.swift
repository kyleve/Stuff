import RegionKit
import SwiftUI
import WhereCore

/// Expanded forecast rows and planning controls shared by Locations and Your Year.
struct LocationForecastContent: View {
    let forecasts: [LocationForecast]
    var homeRegion: Region?
    var planningAction: (() -> Void)?

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.locationForecast.rowSpacing) {
            ForEach(forecasts, id: \.region) { forecast in
                LocationForecastRow(forecast: forecast, homeRegion: homeRegion)
            }

            if forecasts.contains(where: { !$0.estimatedTotalDays.isExact }) {
                Text(String(localized: .forecastDateRangeExplanation))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let planningAction {
                LocationForecastControls(planningAction: planningAction)
            }
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        LocationForecastContent(
            forecasts: report.forecasts.leadingForecasts(report: report.report),
            homeRegion: report.forecasts.planning.homeRegion,
            planningAction: {},
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
