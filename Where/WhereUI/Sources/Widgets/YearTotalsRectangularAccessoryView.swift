import StuffCore
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
            Label(
                LocalizedStrings.Widget.yearEmpty.localized,
                systemImage: "calendar.badge.exclamationmark",
            )
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
                        LocalizedStrings.Common.regionDaysAccessibility(
                            region: entry.region.localizedName,
                            days: entry.days,
                        ).localized,
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
    #Preview("Ranked", traits: .fixedLayout(width: 170, height: 80)) {
        YearTotalsRectangularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot())
    }

    #Preview("Empty", traits: .fixedLayout(width: 170, height: 80)) {
        YearTotalsRectangularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
            dayRegions: [],
            totals: [:],
        ))
    }
#endif
