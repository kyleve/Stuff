import SwiftUI

/// One stop on the year journey: a connected region marker, its date span, and
/// a compact badge for the number of consecutive days.
struct PresenceJourneyRow: View {
    let stint: RegionStint
    let calendar: Calendar
    let daysInYear: Int
    let isFirst: Bool
    let isLast: Bool
    let cardPosition: PresenceJourneyCardPosition

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let timeline = stylesheet.timeline
        let rail = timeline.rail
        let row = timeline.row
        let style = regionStyles.style(for: stint.region)
        let dateRange = DateRangeFormatting.abbreviated(
            start: stint.start,
            end: stint.end,
            calendar: calendar,
        )
        let countLayout = row.stacksDayCount
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: row.labelSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: row.spacing))
        let proportionalHeight = row.baseHeight
            + row.yearScaleHeight * CGFloat(stint.dayCount) / CGFloat(daysInYear)
        let cardShape = cardPosition.shape(cornerRadius: row.cornerRadius)

        HStack(spacing: rail.toCardSpacing) {
            Color.clear
                .frame(width: rail.nodeSize)

            countLayout {
                VStack(alignment: .leading, spacing: row.labelSpacing) {
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
                    .padding(.horizontal, row.countHorizontalPadding)
                    .padding(.vertical, row.countVerticalPadding)
                    .background {
                        Capsule()
                            .fill(style.tint.opacity(row.countFillOpacity))
                    }
            }
            .frame(minHeight: proportionalHeight)
            .padding(.horizontal, row.horizontalPadding)
            .padding(.vertical, row.verticalPadding)
            .background {
                cardShape.fill(style.tint.opacity(row.fillOpacity))
            }
            .overlay {
                PresenceJourneyCardBorder(
                    position: cardPosition,
                    cornerRadius: row.cornerRadius,
                    color: style.tint.opacity(row.borderOpacity),
                    lineWidth: row.borderWidth,
                )
            }
        }
        .padding(cardPosition.gapEdges, row.gap / 2)
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
                cardPosition: .standalone,
            )
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif
