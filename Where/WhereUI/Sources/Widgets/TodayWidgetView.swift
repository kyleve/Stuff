import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Home-screen widget content: which region(s) today already counts for.
/// Renders from a `WidgetSnapshot` value, so the widget extension's
/// `TimelineProvider` owns all I/O and this view stays trivially hostable
/// in previews and tests. Deliberately lighter than the app's passport
/// cards — no Canvas, glass, or shadows — to respect the widget render
/// budget.
public struct TodayWidgetView: View {
    private let snapshot: WidgetSnapshot

    public init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var regions: [Region] {
        snapshot.orderedDayRegions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: .widgetTodayTitle))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(snapshot.day, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if let hero = regions.first, regions.count == 1 {
                heroRegion(hero)
            } else if regions.isEmpty {
                emptyContent
            } else {
                regionList
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The common case — one region so far today — gets the full passport
    /// treatment: big emoji, serif uppercase name in the region's tint.
    private func heroRegion(_ region: Region) -> some View {
        let style = regionStyles.style(for: region)
        return VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Text(style.emoji)
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(region.localizedName)
                .font(stylesheet.typography.widgetHeroRegion)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(style.tint)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
    }

    /// A multi-region day (e.g. a CA→NY flight) lists each region compactly.
    private var regionList: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            ForEach(regions, id: \.self) { region in
                let style = regionStyles.style(for: region)
                HStack(spacing: stylesheet.spacing.small) {
                    Text(style.emoji)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(region.localizedName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(style.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Image(systemSymbol: .locationSlash)
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(String(localized: .widgetTodayEmpty))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    extension TodayWidgetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "SingleRegion",
                configurations: .componentDefaults,
                settle: .immediate,
            ) {
                TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california],
                    totals: [.california: 132],
                ))
            }
            whereSnapshot(
                name: "MultiRegion",
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california, .newYork],
                    totals: [.california: 132, .newYork: 41],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark, settle: .immediate) {
                TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [],
                    totals: [:],
                ))
            }
        }
    }

    #Preview {
        TodayWidgetView.snapshotPreviews
    }
#endif

#if DEBUG
    extension TodayWidgetView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            TodayWidgetView.self,
            title: "Today Widget",
            viewport: .fixed(CGSize(width: 338, height: 158)),
            navigationContainer: .none,
        )
    }
#endif
