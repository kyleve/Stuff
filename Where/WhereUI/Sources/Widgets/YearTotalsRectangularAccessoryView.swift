import SwiftUI
import WhereCore

/// Lock-screen rectangular accessory: up to three ranked region day counts,
/// one per line. Same ranking as the home-screen widget, compressed to the
/// rectangular slot's three monochrome lines.
public struct YearTotalsRectangularAccessoryView: View {
    /// The rectangular slot fits three text lines.
    private static let maxRows = 3

    private let snapshot: WidgetSnapshot

    public init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    private var ranked: [RegionDays] {
        snapshot.rankedTotals(maxRows: Self.maxRows)
    }

    public var body: some View {
        if ranked.isEmpty {
            Label(Strings.widgetYearEmpty, systemImage: "calendar.badge.exclamationmark")
                .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ranked) { entry in
                    HStack(spacing: UIConstants.Spacings.xSmall) {
                        Image(systemName: entry.region.style.symbolName)
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(entry.region.localizedName)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: UIConstants.Spacings.xSmall)
                        Text(entry.days, format: .number)
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
    #Preview("Ranked", traits: .fixedLayout(width: 170, height: 80)) {
        YearTotalsRectangularAccessoryView(snapshot: WidgetSnapshot(
            day: .now,
            year: 2026,
            dayRegions: [.california],
            totals: [.california: 132, .newYork: 41, .canada: 9, .other: 2],
        ))
    }

    #Preview("Empty", traits: .fixedLayout(width: 170, height: 80)) {
        YearTotalsRectangularAccessoryView(snapshot: WidgetSnapshot(
            day: .now,
            year: 2026,
            dayRegions: [],
            totals: [:],
        ))
    }
#endif
