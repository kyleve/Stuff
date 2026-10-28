import Foundation
import RegionKit
import WhereCore

/// One spoken month summary. Runs follow the displayed region and planning
/// membership; badges retain their dates without splitting a continuous stay.
struct CalendarMonthAccessibility {
    let label: String
    let value: String

    init(
        month: CalendarMonth,
        calendar: Calendar,
        memberships: (CalendarDayCell) -> [Region: PlanningDayPresence.Membership],
        planningSummary: [PlanningRegionSummary],
    ) {
        label = WhereFormat.calendarMonthLabel(
            month: month,
            planningSummary: planningSummary,
            calendar: calendar,
        )
        var spans: [Span] = []
        for cell in month.days {
            let day = CalendarDay(from: cell.date, in: calendar)
            let planned = memberships(cell)
            let presence = Presence(
                regions: Region.inCanonicalOrder(Set(cell.regions).union(planned.keys)),
                memberships: planned,
                needsAttention: cell.needsAttention,
            )
            if let last = spans.last,
               last.presence == presence,
               last.dates.upperBound.adding(days: 1) == day
            {
                spans[spans.count - 1].append(cell, day: day)
            } else {
                var span = Span(dates: day ... day, presence: presence)
                span.append(cell, day: day)
                spans.append(span)
            }
        }
        value = spans.compactMap { $0.summary(calendar: calendar) }.joined(separator: "; ")
    }

    private struct Presence: Equatable {
        let regions: [Region]
        let memberships: [Region: PlanningDayPresence.Membership]
        let needsAttention: Bool
    }

    private struct Span {
        var dates: ClosedRange<CalendarDay>
        let presence: Presence
        var attachmentDays: [CalendarDay] = []
        var flightDays: [CalendarDay] = []

        mutating func append(_ cell: CalendarDayCell, day: CalendarDay) {
            dates = dates.lowerBound ... day
            if cell.hasEvidence { attachmentDays.append(day) }
            if cell.hasFlight { flightDays.append(day) }
        }

        func summary(calendar: Calendar) -> String? {
            var components = presence.regions.map { region in
                guard let membership = presence.memberships[region] else {
                    return region.localizedName
                }
                return String(localized: .planningCalendarMonthSummary(
                    region.localizedName,
                    WhereFormat.planningMembership(membership),
                ))
            }
            if presence.needsAttention {
                components.append(String(localized: .calendarSpanNeedsLocationAccessibility))
            }
            if !attachmentDays.isEmpty {
                components.append(WhereFormat.calendarBadgeAccessibility(
                    badge: String(localized: .calendarAttachmentAccessibility),
                    dates: badgeDates(attachmentDays, calendar: calendar),
                ))
            }
            if !flightDays.isEmpty {
                components.append(WhereFormat.calendarBadgeAccessibility(
                    badge: String(localized: .historyFlight),
                    dates: badgeDates(flightDays, calendar: calendar),
                ))
            }
            guard !components.isEmpty else { return nil }
            return WhereFormat.calendarSpanAccessibility(
                dates: dates,
                details: components,
                calendar: calendar,
            )
        }

        private func badgeDates(_ days: [CalendarDay], calendar: Calendar) -> String {
            var ranges: [ClosedRange<CalendarDay>] = []
            for day in days {
                if let last = ranges.last, last.upperBound.adding(days: 1) == day {
                    ranges[ranges.count - 1] = last.lowerBound ... day
                } else {
                    ranges.append(day ... day)
                }
            }
            return ranges.map { WhereFormat.calendarDateRange($0, calendar: calendar) }
                .formatted(.list(type: .and))
        }
    }
}
