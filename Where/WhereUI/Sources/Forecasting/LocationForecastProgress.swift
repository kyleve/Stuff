import SwiftUI
import WhereCore

/// A full-year security rule: recorded days are solid ink and the annual
/// estimate extends behind them as a hatched endorsement.
struct LocationForecastProgress: View {
    let forecast: LocationForecast
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locationForecast
        let progress = style.progress
        let recordedFraction = fraction(forecast.yearToDateDays)
        let estimatedFraction = forecast.estimatedFractionOfYear

        GeometryReader { proxy in
            let recordedWidth = proxy.size.width * recordedFraction
            let estimatedWidth = proxy.size.width * estimatedFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(style.ink.progressTrackOpacity))

                if estimatedWidth > 0 {
                    Capsule()
                        .fill(tint.opacity(style.ink.progressEstimateFillOpacity))
                        .frame(width: estimatedWidth)
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

                if recordedWidth > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: recordedWidth)
                }
            }
        }
        .frame(height: progress.height)
        .accessibilityHidden(true)
    }

    private func fraction(_ days: Int) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let daysInYear = calendar.dayCount(ofYear: forecast.year)
        guard daysInYear > 0 else { return 0 }
        return min(1, max(0, Double(days) / Double(daysInYear)))
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        if let forecast = report.forecasts.leadingForecasts(report: report.report).first {
            LocationForecastProgress(forecast: forecast, tint: .orange)
                .padding()
                .whereBroadwayRoot()
        }
    }
#endif
