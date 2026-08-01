import Charts
import RegionKit
import SwiftUI
import WhereCore

/// The dense 12×31 plot and its coordinate-to-day selection gesture.
struct YearHeatmapChart: View {
    let overview: YearOverview
    let calendar: Calendar
    @Binding var selectedDayID: CalendarDay?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var style: WhereStylesheet.YearOverviewStyle {
        stylesheet.yearOverview
    }

    var body: some View {
        Chart {
            ForEach(overview.days) { day in
                if selectedDayID == day.id {
                    RectangleMark(
                        xStart: .value(
                            "Selection start",
                            Double(day.id.day)
                                - Double(style.heatmap.selectionWidthRatio) / 2,
                        ),
                        xEnd: .value(
                            "Selection end",
                            Double(day.id.day)
                                + Double(style.heatmap.selectionWidthRatio) / 2,
                        ),
                        yStart: .value(
                            "Selection row start",
                            row(for: day.id.month)
                                - Double(style.heatmap.selectionHeightRatio) / 2,
                        ),
                        yEnd: .value(
                            "Selection row end",
                            row(for: day.id.month)
                                + Double(style.heatmap.selectionHeightRatio) / 2,
                        ),
                    )
                    .foregroundStyle(Color.primary)
                    .cornerRadius(style.heatmap.cellCornerRadius)
                    .accessibilityHidden(true)
                }

                RectangleMark(
                    xStart: .value(
                        "Day start",
                        Double(day.id.day) - Double(style.heatmap.cellWidthRatio) / 2,
                    ),
                    xEnd: .value(
                        "Day end",
                        Double(day.id.day) + Double(style.heatmap.cellWidthRatio) / 2,
                    ),
                    yStart: .value(
                        "Month row start",
                        row(for: day.id.month) - Double(style.heatmap.cellHeightRatio) / 2,
                    ),
                    yEnd: .value(
                        "Month row end",
                        row(for: day.id.month) + Double(style.heatmap.cellHeightRatio) / 2,
                    ),
                )
                .foregroundStyle(fill(for: day.kind))
                .cornerRadius(style.heatmap.cellCornerRadius)
                .accessibilityLabel(dayAccessibility(day))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: 0.5 ... 31.5)
        .chartYScale(domain: 0.5 ... 12.5)
        .chartXAxis {
            AxisMarks(values: [1, 5, 10, 15, 20, 25, 31]) { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(1 ... 12)) { value in
                AxisValueLabel {
                    if let position = value.as(Int.self) {
                        Text(monthSymbol(forRow: position))
                    }
                }
            }
        }
        // The plot has twelve fixed-height rows. Keep its supplementary axis
        // labels compact while the selectable callout and legend continue to
        // honor the user's full Dynamic Type size.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .aspectRatio(style.heatmap.plotAspectRatio, contentMode: .fit)
        .chartGesture { proxy in
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    select(at: value.location, proxy: proxy)
                }
        }
        .accessibilityLabel(String(localized: .yearHeatmapAccessibilityLabel))
        .accessibilityHint(String(localized: .yearHeatmapAccessibilityHint))
    }

    private func row(for month: Int) -> Double {
        Double(13 - month)
    }

    private func monthSymbol(forRow row: Int) -> String {
        let month = 13 - row
        guard calendar.shortMonthSymbols.indices.contains(month - 1) else { return "" }
        return calendar.shortMonthSymbols[month - 1]
    }

    private func select(at location: CGPoint, proxy: ChartProxy) {
        guard let (dayValue, rowValue) = proxy.value(
            at: location,
            as: (Double, Double).self,
        ) else {
            selectedDayID = nil
            return
        }
        let dayOfMonth = Int(dayValue.rounded())
        let month = 13 - Int(rowValue.rounded())
        selectedDayID = overview.day(month: month, dayOfMonth: dayOfMonth)?.id
    }

    private func fill(for kind: YearOverview.Day.Kind) -> AnyShapeStyle {
        switch kind {
            case let .region(region):
                return AnyShapeStyle(regionStyles.style(for: region).tint)
            case let .multipleLocations(regions):
                let count = CGFloat(regions.count)
                let stops = regions.enumerated().flatMap { index, region in
                    let start = CGFloat(index) / count
                    let end = CGFloat(index + 1) / count
                    let color = regionStyles.style(for: region).tint
                    return [
                        Gradient.Stop(color: color, location: start),
                        Gradient.Stop(color: color, location: end),
                    ]
                }
                return AnyShapeStyle(LinearGradient(
                    gradient: Gradient(stops: stops),
                    startPoint: .leading,
                    endPoint: .trailing,
                ))
            case .unrecorded:
                return AnyShapeStyle(style.unrecordedColor)
            case .remaining:
                return AnyShapeStyle(style.remainingColor)
        }
    }

    private func dayAccessibility(_ day: YearOverview.Day) -> String {
        WhereFormat.yearOverviewDayAccessibility(
            date: day.id.startOfDay(in: calendar),
            kind: day.kind,
        )
    }
}

#if DEBUG
    #Preview {
        let model = PreviewSupport.loadedYearReportModel()
        YearHeatmapChart(
            overview: PreviewSupport.loadedYearOverview(),
            calendar: model.calendar,
            selectedDayID: .constant(CalendarDay(year: 2026, month: 1, day: 1)),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
