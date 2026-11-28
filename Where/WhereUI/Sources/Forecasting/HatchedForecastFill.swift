import SwiftUI

struct HatchedForecastFill: View {
    let tint: Color
    let width: CGFloat
    let style: WhereStylesheet.LocationForecastStyle

    var body: some View {
        let progress = style.progress
        Capsule()
            .fill(tint.opacity(style.ink.progressEstimateFillOpacity))
            .frame(width: width)
            .overlay {
                Canvas { context, size in
                    for x in stride(
                        from: -size.height,
                        through: size.width,
                        by: progress.hatchSpacing,
                    ) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(
                            path,
                            with: .color(tint.opacity(
                                style.ink.progressHatchOpacity,
                            )),
                            lineWidth: progress.hatchLineWidth,
                        )
                    }
                }
                .clipShape(.capsule)
            }
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
