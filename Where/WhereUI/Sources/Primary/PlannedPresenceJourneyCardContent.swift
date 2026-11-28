import SwiftUI
import WhereCore

/// Lays out a planned stay as a full row or a compact joined continuation.
struct PlannedPresenceJourneyCardContent: View {
    let regionName: String
    let dateRange: String
    let dayCount: DayBounds
    let detailLabel: String
    let daysInYear: Int
    let position: PresenceJourneyCardPosition
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let timeline = stylesheet.timeline
        let row = timeline.row
        let planned = timeline.planned
        let countLayout = row.stacksDayCount
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: row.labelSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: row.spacing))
        let baseHeight = position.isJoinedContinuation
            ? planned.joinedBaseHeight
            : row.baseHeight
        let proportionalHeight = baseHeight
            + row.yearScaleHeight * CGFloat(dayCount.upper) / CGFloat(daysInYear)

        countLayout {
            if position.isJoinedContinuation {
                JoinedPlanLabels(
                    regionName: regionName,
                    dateRange: dateRange,
                    row: row,
                    planned: planned,
                )
                JourneyDayCountBadge(
                    text: WhereFormat.dayCount(dayCount),
                    font: .caption.bold(),
                    horizontalPadding: planned.joinedCountHorizontalPadding,
                    verticalPadding: planned.joinedCountVerticalPadding,
                    fill: tint.opacity(row.countFillOpacity / 2),
                )

            } else {
                PlannedJourneyLabels(
                    regionName: regionName,
                    dateRange: dateRange,
                    detailLabel: detailLabel,
                    row: row,
                    planned: planned,
                )
                JourneyDayCountBadge(
                    text: WhereFormat.dayCount(dayCount),
                    font: .subheadline.bold(),
                    horizontalPadding: row.countHorizontalPadding,
                    verticalPadding: row.countVerticalPadding,
                    fill: tint.opacity(row.countFillOpacity / 2),
                )
            }
        }
        .frame(minHeight: proportionalHeight)
        .padding(.horizontal, row.horizontalPadding)
        .padding(
            .vertical,
            position.isJoinedContinuation
                ? planned.joinedVerticalPadding
                : row.verticalPadding,
        )
    }
}

private struct PlannedJourneyLabels: View {
    let regionName: String
    let dateRange: String
    let detailLabel: String
    let row: WhereStylesheet.TimelineStyle.Row
    let planned: WhereStylesheet.TimelineStyle.Planned

    var body: some View {
        VStack(alignment: .leading, spacing: row.labelSpacing) {
            Text(regionName)
                .font(.headline)
            Text(dateRange)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(detailLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(planned.labelOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 0) {
            PlannedPresenceJourneyCardContent(
                regionName: "New York",
                dateRange: "Jul 16 – Aug 15",
                dayCount: DayBounds(exact: 31),
                detailLabel: String(localized: .planningCalendarPlanned),
                daysInYear: 365,
                position: .bottom,
                tint: .blue,
            )
            PlannedPresenceJourneyCardContent(
                regionName: "New York",
                dateRange: "Jul 16 – Aug 15",
                dayCount: DayBounds(exact: 31),
                detailLabel: String(localized: .planningCalendarPlanned),
                daysInYear: 365,
                position: .standalone,
                tint: .blue,
            )
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
