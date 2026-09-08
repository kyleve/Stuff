import SwiftUI

/// Lays out a planned stay as a full row or a compact joined continuation.
struct PlannedPresenceJourneyCardContent: View {
    let regionName: String
    let dateRange: String
    let dayCount: Int
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
            + row.yearScaleHeight * CGFloat(dayCount) / CGFloat(daysInYear)

        countLayout {
            if position.isJoinedContinuation {
                if row.stacksDayCount {
                    VStack(alignment: .leading, spacing: row.labelSpacing) {
                        Text(regionName)
                            .font(.subheadline.bold())
                        Text(dateRange)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: planned.joinedLabelSpacing) {
                        Text(regionName)
                            .font(.subheadline.bold())
                            .layoutPriority(1)
                        Text(dateRange)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(WhereFormat.dayCount(dayCount))
                    .font(.caption.bold())
                    .monospacedDigit()
                    .padding(.horizontal, planned.joinedCountHorizontalPadding)
                    .padding(.vertical, planned.joinedCountVerticalPadding)
                    .background {
                        Capsule()
                            .fill(tint.opacity(row.countFillOpacity / 2))
                    }
            } else {
                VStack(alignment: .leading, spacing: row.labelSpacing) {
                    Text(regionName)
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

                Text(WhereFormat.dayCount(dayCount))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .padding(.horizontal, row.countHorizontalPadding)
                    .padding(.vertical, row.countVerticalPadding)
                    .background {
                        Capsule()
                            .fill(tint.opacity(row.countFillOpacity / 2))
                    }
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

#if DEBUG
    #Preview {
        VStack(spacing: 0) {
            PlannedPresenceJourneyCardContent(
                regionName: "New York",
                dateRange: "Jul 16 – Aug 15",
                dayCount: 31,
                daysInYear: 365,
                position: .bottom,
                tint: .blue,
            )
            PlannedPresenceJourneyCardContent(
                regionName: "New York",
                dateRange: "Jul 16 – Aug 15",
                dayCount: 31,
                daysInYear: 365,
                position: .standalone,
                tint: .blue,
            )
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
