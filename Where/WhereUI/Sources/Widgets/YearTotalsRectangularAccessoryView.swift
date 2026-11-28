import SFSafeSymbols
import SnapshotKit
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
        Group {
            if ranked.isEmpty {
                YearTotalsAccessoryEmptyState()
            } else {
                YearTotalsAccessoryRows(ranked: ranked)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WhereFormat.widgetYearTitle(year: snapshot.year))
        .accessibilityValue(WhereFormat.widgetYearAccessibilityValue(entries: ranked))
    }
}

private struct YearTotalsAccessoryRow: View {
    let entry: RegionDays

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        HStack(spacing: stylesheet.spacing.xSmall) {
            Image(systemSymbol: regionStyles.style(for: entry.region).symbol)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(entry.region.localizedName)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: stylesheet.spacing.xSmall)
            Text(entry.days, format: .number)
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
    }
}

private struct YearTotalsAccessoryEmptyState: View {
    var body: some View {
        Label(
            String(localized: .widgetYearEmpty),
            systemSymbol: .calendarBadgeExclamationmark,
        )
        .font(.caption)
    }
}

private struct YearTotalsAccessoryRows: View {
    let ranked: [RegionDays]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ranked) { entry in
                YearTotalsAccessoryRow(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    extension YearTotalsRectangularAccessoryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Ranked",
                configurations: .componentLightDarkWithAnnotations,
                settle: .immediate,
            ) {
                YearTotalsRectangularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california],
                    totals: [.california: 132, .newYork: 41, .ontario: 9, .other: 2],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark, settle: .immediate) {
                YearTotalsRectangularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [],
                    totals: [:],
                ))
            }
        }
    }

    #Preview {
        YearTotalsRectangularAccessoryView.snapshotPreviews
    }
#endif

#if DEBUG
    extension YearTotalsRectangularAccessoryView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            YearTotalsRectangularAccessoryView.self,
            title: "Year Totals Rectangular",
            viewport: .fixed(CGSize(width: 338, height: 76)),
            navigationContainer: .none,
        )
    }
#endif
