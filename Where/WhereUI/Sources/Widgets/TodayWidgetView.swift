import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Home-screen widget content: which region(s) today already counts for.
/// Renders as a lightweight folio record from a `WidgetSnapshot`, so the
/// extension owns all I/O while the shared view keeps the app and widget
/// gallery visually identical. It deliberately avoids Canvas and card effects.
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
        let style = stylesheet.homeWidget
        VStack(alignment: .leading, spacing: style.contentSpacing) {
            header

            Rectangle()
                .fill(ruleTint.opacity(style.ruleOpacity))
                .frame(height: style.ruleHeight)
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WhereFormat.widgetTodayAccessibilityLabel(date: snapshot.day))
        .accessibilityValue(WhereFormat.widgetTodayAccessibilityValue(regions: regions))
    }

    @ViewBuilder private var header: some View {
        let style = stylesheet.homeWidget
        if style.stacksHeader {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                recordLabel
                recordDate
            }
        } else {
            HStack(alignment: .center, spacing: style.headerSpacing) {
                recordLabel
                Spacer(minLength: 0)
                recordDate
            }
        }
    }

    private var recordLabel: some View {
        let style = stylesheet.homeWidget
        return HStack(spacing: style.headerSpacing) {
            WhereSeal(tint: stylesheet.palette.brand.brass)
                .frame(width: style.headerSealSize, height: style.headerSealSize)
            Text(String(localized: .widgetTodayTitle))
                .font(style.eyebrowFont)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(stylesheet.palette.brand.ink)
        }
    }

    private var recordDate: some View {
        Text(snapshot.day, format: .dateTime.month(.abbreviated).day())
            .font(stylesheet.homeWidget.dateFont)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var ruleTint: Color {
        guard let first = regions.first else { return stylesheet.palette.brand.brass }
        return regionStyles.style(for: first).tint
    }

    /// The common one-region case lets the editorial name lead; the symbol is
    /// the route marker and the user's emoji survives only as a small charm.
    private func heroRegion(_ region: Region) -> some View {
        let widgetStyle = stylesheet.homeWidget
        let style = regionStyles.style(for: region)
        return HStack(alignment: .center, spacing: stylesheet.spacing.medium) {
            Text(region.localizedName)
                .font(widgetStyle.heroNameFont)
                .foregroundStyle(style.tint)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)

            HStack(spacing: stylesheet.spacing.xSmall) {
                routeMarker(for: region)
                Text(style.emoji)
                    .font(widgetStyle.charmFont)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A multi-region day (e.g. a CA→NY flight) lists each region compactly.
    private var regionList: some View {
        VStack(alignment: .leading, spacing: stylesheet.homeWidget.rowSpacing) {
            ForEach(regions, id: \.self) { region in
                let style = regionStyles.style(for: region)
                HStack(spacing: stylesheet.spacing.medium) {
                    routeMarker(for: region)
                    Text(style.emoji)
                        .font(stylesheet.homeWidget.charmFont)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .accessibilityHidden(true)
                    Text(region.localizedName)
                        .font(stylesheet.homeWidget.rowNameFont)
                        .foregroundStyle(style.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(region.localizedName)
            }
        }
    }

    private func routeMarker(for region: Region) -> some View {
        let widgetStyle = stylesheet.homeWidget
        let regionStyle = regionStyles.style(for: region)
        return Image(systemName: regionStyle.symbolName)
            .font(.system(size: widgetStyle.routeSymbolPointSize, weight: .semibold))
            .foregroundStyle(regionStyle.tint)
            .frame(width: widgetStyle.routeMarkerSize, height: widgetStyle.routeMarkerSize)
            .background(regionStyle.tint.opacity(0.08), in: .circle)
            .overlay {
                Circle()
                    .stroke(regionStyle.tint.opacity(0.24), lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Image(systemSymbol: .locationSlash)
                .font(.title3)
                .foregroundStyle(stylesheet.palette.brand.mineral)
                .accessibilityHidden(true)
            Text(String(localized: .widgetTodayEmpty))
                .font(stylesheet.homeWidget.rowNameFont)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    extension TodayWidgetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "SingleRegion",
                configurations: .componentDefaults + SnapshotConfiguration.combinations(
                    layoutDirections: [.rightToLeft],
                ),
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
