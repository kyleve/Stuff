import SwiftUI

struct ForecastPanelPaper: View {
    let style: WhereStylesheet.LocationForecastStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)
        ZStack {
            shape.fill(.background)
            if style.ink.surfaceWashOpacity > 0 {
                LinearGradient(
                    colors: [
                        Color.primary.opacity(style.ink.surfaceWashOpacity),
                        .clear,
                        Color.primary.opacity(style.ink.surfaceWashOpacity * 0.45),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
            }
            SecurityPrintRosette(
                tint: .primary,
                wobble: style.surface.rosetteWobble,
                lineWidth: style.surface.rosetteLineWidth,
                primaryRingSpacing: style.surface.primaryRingSpacing,
                secondaryRingSpacing: style.surface.secondaryRingSpacing,
                primaryOpacity: style.ink.rosettePrimaryOpacity,
                secondaryOpacity: style.ink.rosetteSecondaryOpacity,
            )
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

#if DEBUG
    #Preview("Forecast") {
        let report = PreviewSupport.plannedStayYearReportModel()
        LocationForecastPanel(
            forecasts: report.primaryRegionForecasts,
            microprintRegions: report.ranking.primary.map(\.region),
            homeRegion: report.forecasts.planning.homeRegion,
        )
        .whereBroadwayRoot()
    }
#endif
