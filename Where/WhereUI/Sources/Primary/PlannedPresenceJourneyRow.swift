import RegionKit
import SwiftUI
import WhereCore

/// A lighter hatched journey row for the future slice of a planned stay.
struct PlannedPresenceJourneyRow: View {
    let item: PlanningTimelineItem
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
        let planned = timeline.planned
        let style = regionStyles.style(for: item.region)
        let start = item.start.startOfDay(in: calendar)
        let end = item.end.startOfDay(in: calendar)
        let dateRange = DateRangeFormatting.abbreviated(
            start: start,
            end: end,
            calendar: calendar,
        )
        HStack(spacing: rail.toCardSpacing) {
            Color.clear
                .frame(width: rail.nodeSize)

            PlannedPresenceJourneyCardContent(
                regionName: item.region.localizedName,
                dateRange: dateRange,
                dayCount: item.dayCount,
                detailLabel: WhereFormat.planningMembership(item.membership),
                daysInYear: daysInYear,
                position: cardPosition,
                tint: style.tint,
            )
            .background {
                PlannedPresenceJourneyBackground(
                    position: cardPosition,
                    tint: style.tint,
                )
            }
            .overlay {
                PresenceJourneyCardBorder(
                    position: cardPosition,
                    cornerRadius: row.cornerRadius,
                    color: style.tint.opacity(planned.borderOpacity),
                    lineWidth: row.borderWidth,
                )
            }
        }
        .padding(cardPosition.gapEdges, row.gap / 2)
        .background(alignment: .leading) {
            PresenceJourneyRail(
                tint: style.tint.opacity(planned.labelOpacity),
                emoji: style.emoji,
                isFirst: isFirst,
                isLast: isLast,
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            item.region.localizedName,
            dateRange,
            WhereFormat.dayCount(item.dayCount),
            WhereFormat.planningMembership(item.membership),
        ].joined(separator: ", "))
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        if let item = PlanningTimelineItem.items(
            planning: report.forecasts.planning,
            year: PreviewSupport.year,
            today: report.forecasts.today,
        ).first {
            PlannedPresenceJourneyRow(
                item: item,
                calendar: report.calendar,
                daysInYear: 365,
                isFirst: true,
                isLast: true,
                cardPosition: .standalone,
            )
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif
