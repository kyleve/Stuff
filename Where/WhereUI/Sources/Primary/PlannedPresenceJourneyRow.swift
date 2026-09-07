import RegionKit
import SwiftUI
import WhereCore

/// A lighter hatched journey row for the future slice of a planned stay.
struct PlannedPresenceJourneyRow: View {
    let interval: LocationForecastModel.PlannedInterval
    let calendar: Calendar
    let daysInYear: Int
    let isFirst: Bool
    let cardPosition: PresenceJourneyCardPosition

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let timeline = stylesheet.timeline
        let rail = timeline.rail
        let row = timeline.row
        let planned = timeline.planned
        let style = regionStyles.style(for: interval.region)
        let start = interval.start.startOfDay(in: calendar)
        let end = interval.end.startOfDay(in: calendar)
        let dateRange = DateRangeFormatting.abbreviated(
            start: start,
            end: end,
            calendar: calendar,
        )
        HStack(spacing: rail.toCardSpacing) {
            Color.clear
                .frame(width: rail.nodeSize)

            PlannedPresenceJourneyCardContent(
                regionName: interval.region.localizedName,
                dateRange: dateRange,
                dayCount: interval.dayCount,
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
                isLast: true,
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            WhereFormat.timelinePlannedRowAccessibility(
                region: interval.region.localizedName,
                range: dateRange,
                days: interval.dayCount,
            ),
        )
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 0) {
            PlannedPresenceJourneyRow(
                interval: LocationForecastModel.PlannedInterval(
                    region: .newYork,
                    start: CalendarDay(year: 2026, month: 7, day: 16),
                    end: CalendarDay(year: 2026, month: 8, day: 15),
                ),
                calendar: Calendar(identifier: .gregorian),
                daysInYear: 365,
                isFirst: false,
                cardPosition: .standalone,
            )
            PlannedPresenceJourneyRow(
                interval: LocationForecastModel.PlannedInterval(
                    region: .newYork,
                    start: CalendarDay(year: 2026, month: 7, day: 16),
                    end: CalendarDay(year: 2026, month: 7, day: 24),
                ),
                calendar: Calendar(identifier: .gregorian),
                daysInYear: 365,
                isFirst: false,
                cardPosition: .bottom,
            )
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
