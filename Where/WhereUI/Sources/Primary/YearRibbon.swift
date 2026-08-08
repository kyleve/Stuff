import RegionKit
import SwiftUI
import WhereCore

/// A compact, calendar-proportional overview of the selected year's stays.
/// Empty portions remain visible, so the ribbon shows both travel and gaps.
struct YearRibbon: View {
    let days: [DayPresence]
    let year: Int
    let calendar: Calendar

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let timeline = stylesheet.timeline
        let monthStarts = (1 ... 12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }

        VStack(alignment: .leading, spacing: timeline.overviewSpacing) {
            Text(WhereFormat.yearText(year))
                .font(timeline.overviewYearFont)
                .monospacedDigit()

            VStack(spacing: timeline.monthLabelSpacing) {
                HStack(spacing: 0) {
                    ForEach(monthStarts, id: \.self) { month in
                        Text(month, format: .dateTime.month(.narrow))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                GeometryReader { _ in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(timeline.ribbonTrack)

                        Canvas { context, size in
                            let daysInYear = calendar.dayCount(ofYear: year)
                            for day in days {
                                let date = day.startOfDay(in: calendar)
                                guard let ordinal = calendar.ordinality(
                                    of: .day,
                                    in: .year,
                                    for: date,
                                ) else { continue }

                                let regions = Region.inCanonicalOrder(day.regions)
                                for (lane, region) in regions.enumerated() {
                                    let rect = YearRibbonLayout.segmentRect(
                                        ordinal: ordinal,
                                        daysInYear: daysInYear,
                                        size: size,
                                        lane: lane,
                                        laneCount: regions.count,
                                    )
                                    context.fill(
                                        Path(rect),
                                        with: .color(regionStyles.style(for: region).tint),
                                    )
                                }
                            }
                        }
                    }
                    .clipShape(.capsule)
                    .overlay {
                        Capsule()
                            .stroke(
                                timeline.ribbonBorder,
                                lineWidth: timeline.ribbonBorderWidth,
                            )
                    }
                }
                .frame(height: timeline.ribbonHeight)
            }
            .accessibilityHidden(true)
        }
        .padding(timeline.overviewPadding)
        .background {
            RoundedRectangle(cornerRadius: timeline.overviewCornerRadius)
                .fill(timeline.overviewBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: timeline.overviewCornerRadius)
                .stroke(
                    timeline.overviewBorder,
                    lineWidth: timeline.overviewBorderWidth,
                )
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        YearRibbon(
            days: report.report?.days ?? [],
            year: report.selectedYear,
            calendar: report.calendar,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
