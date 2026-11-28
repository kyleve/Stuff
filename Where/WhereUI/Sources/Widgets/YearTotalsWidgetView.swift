import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Home-screen widget content: year-to-date day counts per region — the
/// number a residency-audit user wants at a glance. Renders from a
/// `WidgetSnapshot` value; ranking reuses `RegionRanking.ranked` so the
/// widget orders regions exactly like the app's Locations tab (primary
/// regions first, then Elsewhere).
public struct YearTotalsWidgetView: View {
    private let snapshot: WidgetSnapshot
    private let maxRows: Int

    /// - Parameter maxRows: how many ranked regions fit the widget family
    ///   (the extension passes a per-family value; 4 suits systemSmall).
    public init(snapshot: WidgetSnapshot, maxRows: Int = 4) {
        self.snapshot = snapshot
        self.maxRows = maxRows
    }

    @Environment(\.stylesheet) private var stylesheet

    private var ranked: [RegionDays] {
        snapshot.rankedTotals(maxRows: maxRows)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            HomeWidgetTitle(title: WhereFormat.widgetYearTitle(year: snapshot.year))

            Spacer(minLength: 0)

            if ranked.isEmpty {
                HomeWidgetEmptyState(
                    symbol: .calendarBadgeExclamationmark,
                    title: String(localized: .widgetYearEmpty),
                )
            } else {
                YearTotalsWidgetRows(ranked: ranked)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WhereFormat.widgetYearTitle(year: snapshot.year))
        .accessibilityValue(WhereFormat.widgetYearAccessibilityValue(entries: ranked))
    }
}

private struct YearTotalsWidgetRows: View {
    let ranked: [RegionDays]

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            ForEach(ranked) { entry in
                YearTotalsWidgetRow(entry: entry)
            }
        }
    }
}

private struct YearTotalsWidgetRow: View {
    let entry: RegionDays

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        HStack(spacing: stylesheet.spacing.small) {
            Text(regionStyles.style(for: entry.region).emoji)
                .font(.caption)
                .accessibilityHidden(true)
            Text(entry.region.localizedName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: stylesheet.spacing.small)
            Text(entry.days, format: .number)
                .font(stylesheet.typography.widgetTotalNumber)
                .monospacedDigit()
                .foregroundStyle(regionStyles.style(for: entry.region).tint)
        }
    }
}

#if DEBUG
    extension YearTotalsWidgetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Ranked",
                configurations: .componentRepresentative,
                settle: .immediate,
            ) {
                YearTotalsWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california],
                    totals: [
                        .california: 132,
                        .newYork: 41,
                        .ontario: 9,
                        .europeanUnion: 4,
                        .other: 2,
                    ],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark, settle: .immediate) {
                YearTotalsWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [],
                    totals: [:],
                ))
            }
        }
    }

    #Preview {
        YearTotalsWidgetView.snapshotPreviews
    }
#endif

#if DEBUG
    extension YearTotalsWidgetView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            YearTotalsWidgetView.self,
            title: "Year Totals Widget",
            viewport: .fixed(CGSize(width: 338, height: 158)),
            navigationContainer: .none,
        )
    }
#endif
