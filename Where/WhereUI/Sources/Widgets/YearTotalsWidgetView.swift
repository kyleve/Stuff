import SwiftUI
import WhereCore

/// Home-screen widget content: year-to-date day counts per region — the
/// number a residency-audit user wants at a glance. Renders from a
/// `WidgetSnapshot` value; ranking reuses `RegionRanking.ranked` so the
/// widget orders regions exactly like the app's Primary/Elsewhere tabs.
public struct YearTotalsWidgetView: View {
    private let snapshot: WidgetSnapshot
    private let maxRows: Int

    /// - Parameter maxRows: how many ranked regions fit the widget family
    ///   (the extension passes a per-family value; 4 suits systemSmall).
    public init(snapshot: WidgetSnapshot, maxRows: Int = 4) {
        self.snapshot = snapshot
        self.maxRows = maxRows
    }

    private var ranked: [RegionDays] {
        snapshot.rankedTotals(maxRows: maxRows)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.small) {
            Text(Strings.widgetYearTitle(year: snapshot.year))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if ranked.isEmpty {
                emptyContent
            } else {
                rows
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xSmall) {
            ForEach(ranked) { entry in
                HStack(spacing: UIConstants.Spacings.small) {
                    Text(entry.region.style.emoji)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(entry.region.localizedName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: UIConstants.Spacings.small)
                    Text(entry.days, format: .number)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(entry.region.style.tint)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Strings.regionDaysAccessibility(
                        region: entry.region.localizedName,
                        days: entry.days,
                    ),
                )
            }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xSmall) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(Strings.widgetYearEmpty)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Ranked totals") {
        YearTotalsWidgetView(snapshot: WidgetSnapshot(
            day: .now,
            year: 2026,
            dayRegions: [.california],
            totals: [.california: 132, .newYork: 41, .canada: 9, .europeanUnion: 4, .other: 2],
        ))
        .padding()
    }

    #Preview("Empty") {
        YearTotalsWidgetView(snapshot: WidgetSnapshot(
            day: .now,
            year: 2026,
            dayRegions: [],
            totals: [:],
        ))
        .padding()
    }
#endif
