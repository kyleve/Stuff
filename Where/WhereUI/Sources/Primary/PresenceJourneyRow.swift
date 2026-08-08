import SwiftUI

/// One stop on the year journey: a connected region marker, its date span, and
/// a compact badge for the number of consecutive days.
struct PresenceJourneyRow: View {
    let stint: RegionStint
    let calendar: Calendar
    let daysInYear: Int
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let timeline = stylesheet.timeline
        let style = regionStyles.style(for: stint.region)
        let dateRange = DateRangeFormatting.abbreviated(
            start: stint.start,
            end: stint.end,
            calendar: calendar,
        )
        let countLayout = timeline.stacksDayCount
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: timeline.labelSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: timeline.rowSpacing))
        let proportionalHeight = timeline.rowBaseHeight
            + timeline.rowYearScaleHeight * CGFloat(stint.dayCount) / CGFloat(daysInYear)

        HStack(spacing: timeline.railToCardSpacing) {
            Color.clear
                .frame(width: timeline.nodeSize)

            countLayout {
                VStack(alignment: .leading, spacing: timeline.labelSpacing) {
                    Text(stint.region.localizedName)
                        .font(.headline)
                    Text(dateRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(WhereFormat.dayCount(stint.dayCount))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .padding(.horizontal, timeline.countHorizontalPadding)
                    .padding(.vertical, timeline.countVerticalPadding)
                    .background {
                        Capsule()
                            .fill(style.tint.opacity(timeline.countFillOpacity))
                    }
            }
            .frame(minHeight: proportionalHeight)
            .padding(.horizontal, timeline.rowHorizontalPadding)
            .padding(.vertical, timeline.rowVerticalPadding)
            .background {
                RoundedRectangle(cornerRadius: timeline.rowCornerRadius)
                    .fill(style.tint.opacity(timeline.rowFillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: timeline.rowCornerRadius)
                    .stroke(
                        style.tint.opacity(timeline.rowBorderOpacity),
                        lineWidth: timeline.rowBorderWidth,
                    )
            }
        }
        .padding(.vertical, timeline.rowGap / 2)
        .background(alignment: .leading) {
            PresenceJourneyRail(
                tint: style.tint,
                emoji: style.emoji,
                isFirst: isFirst,
                isLast: isLast,
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            WhereFormat.timelineRowAccessibility(
                region: stint.region.localizedName,
                range: dateRange,
                days: stint.dayCount,
            ),
        )
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        if let yearReport = report.report,
           let stint = PresenceTimeline.stints(from: yearReport).first
        {
            PresenceJourneyRow(
                stint: stint,
                calendar: report.calendar,
                daysInYear: report.daysInSelectedYear,
                isFirst: true,
                isLast: false,
            )
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif
