import SFSafeSymbols
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
        let rail = timeline.rail
        let row = timeline.row
        let style = regionStyles.style(for: stint.region)
        let regionName = stint.region == .other
            ? String(localized: .secondaryTitle)
            : stint.region.localizedName
        let dateRange = DateRangeFormatting.abbreviated(
            start: stint.start,
            end: stint.end,
            calendar: calendar,
        )
        let countLayout = row.stacksDayCount
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: row.labelSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: row.spacing))
        let durationFraction = daysInYear > 0
            ? min(1, CGFloat(stint.dayCount) / CGFloat(daysInYear))
            : 0
        let proportionalHeight = row.baseHeight + row.yearScaleHeight * durationFraction

        HStack(spacing: rail.toCardSpacing) {
            Color.clear
                .frame(width: rail.nodeSize)

            VStack(alignment: .leading, spacing: row.spacing) {
                countLayout {
                    VStack(alignment: .leading, spacing: row.labelSpacing) {
                        Text(regionName)
                            .font(row.regionNameFont)
                            .foregroundStyle(style.tint)
                        Text(dateRange)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(WhereFormat.dayCount(stint.dayCount))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(stylesheet.palette.brand.ink)
                        .padding(.horizontal, row.countHorizontalPadding)
                        .padding(.vertical, row.countVerticalPadding)
                }

                Capsule()
                    .fill(stylesheet.palette.brand.ink.opacity(0.07))
                    .frame(height: row.durationScaleHeight)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(style.tint)
                                .frame(width: proxy.size.width * durationFraction)
                        }
                    }
            }
            .frame(minHeight: proportionalHeight)
            .padding(.horizontal, row.horizontalPadding)
            .padding(.vertical, row.verticalPadding)
            .background {
                RoundedRectangle(cornerRadius: row.cornerRadius)
                    .fill(stylesheet.palette.brand.raisedPaper)
            }
            .optionalGlassSurface(
                row.usesGlassSurface,
                tint: stylesheet.palette.brand.raisedPaper.opacity(0.24),
                in: RoundedRectangle(cornerRadius: row.cornerRadius),
            )
            .overlay {
                RoundedRectangle(cornerRadius: row.cornerRadius)
                    .stroke(
                        stylesheet.palette.brand.ink.opacity(row.borderOpacity),
                        lineWidth: row.borderWidth,
                    )
            }
        }
        .padding(.vertical, row.gap / 2)
        .background(alignment: .leading) {
            PresenceJourneyRail(
                tint: style.tint,
                symbol: style.symbol,
                emoji: style.emoji,
                isFirst: isFirst,
                isLast: isLast,
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            WhereFormat.timelineRowAccessibility(
                region: regionName,
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
