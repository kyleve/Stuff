import RegionKit
import SwiftUI
import WhereCore

/// A lighter hatched journey row for the future slice of a planned stay.
struct PlannedPresenceJourneyRow: View {
    let interval: LocationForecastModel.PlannedInterval
    let calendar: Calendar
    let daysInYear: Int
    let isFirst: Bool

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
        let countLayout = row.stacksDayCount
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: row.labelSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: row.spacing))
        let proportionalHeight = row.baseHeight
            + row.yearScaleHeight * CGFloat(interval.dayCount) / CGFloat(daysInYear)
        let cardShape = RoundedRectangle(cornerRadius: row.cornerRadius)

        HStack(spacing: rail.toCardSpacing) {
            Color.clear
                .frame(width: rail.nodeSize)

            countLayout {
                VStack(alignment: .leading, spacing: row.labelSpacing) {
                    Text(interval.region.localizedName)
                        .font(.headline)
                    Text(dateRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(String(localized: .timelinePlannedStay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(planned.labelOpacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(WhereFormat.dayCount(interval.dayCount))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .padding(.horizontal, row.countHorizontalPadding)
                    .padding(.vertical, row.countVerticalPadding)
                    .background {
                        Capsule()
                            .fill(style.tint.opacity(row.countFillOpacity / 2))
                    }
            }
            .frame(minHeight: proportionalHeight)
            .padding(.horizontal, row.horizontalPadding)
            .padding(.vertical, row.verticalPadding)
            .background {
                ZStack {
                    cardShape
                        .fill(style.tint.opacity(planned.fillOpacity))
                    PlannedStayHatch(
                        color: style.tint,
                        spacing: planned.hatchSpacing,
                        lineWidth: planned.hatchLineWidth,
                        gridOriginX: 0,
                    )
                    .opacity(planned.hatchOpacity)
                    .clipShape(cardShape)
                }
            }
            .overlay {
                cardShape.stroke(
                    style.tint.opacity(planned.borderOpacity),
                    lineWidth: row.borderWidth,
                )
            }
        }
        .padding(.vertical, row.gap / 2)
        .background(alignment: .leading) {
            PresenceJourneyRail(
                tint: style.tint.opacity(planned.labelOpacity),
                symbol: style.symbol,
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
        PlannedPresenceJourneyRow(
            interval: LocationForecastModel.PlannedInterval(
                region: .newYork,
                start: CalendarDay(year: 2026, month: 7, day: 16),
                end: CalendarDay(year: 2026, month: 8, day: 15),
            ),
            calendar: Calendar(identifier: .gregorian),
            daysInYear: 365,
            isFirst: false,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
