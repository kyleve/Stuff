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
    @Environment(\.regionStyles) private var regionStyles

    private var ranked: [RegionDays] {
        snapshot.rankedTotals(maxRows: maxRows)
    }

    public var body: some View {
        let style = stylesheet.homeWidget
        VStack(alignment: .leading, spacing: style.contentSpacing) {
            HStack(spacing: style.headerSpacing) {
                WhereSeal(tint: stylesheet.palette.brand.brass)
                    .frame(width: style.headerSealSize, height: style.headerSealSize)
                Text(WhereFormat.widgetYearTitle(year: snapshot.year))
                    .font(style.eyebrowFont)
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(stylesheet.palette.brand.ink)
            }

            Rectangle()
                .fill(stylesheet.palette.brand.brass.opacity(style.ruleOpacity))
                .frame(height: style.ruleHeight)
                .accessibilityHidden(true)

            if ranked.isEmpty {
                emptyContent
            } else {
                rows
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WhereFormat.widgetYearTitle(year: snapshot.year))
        .accessibilityValue(WhereFormat.widgetYearAccessibilityValue(entries: ranked))
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: stylesheet.homeWidget.rowSpacing) {
            ForEach(ranked) { entry in
                let style = regionStyles.style(for: entry.region)
                HStack(spacing: stylesheet.spacing.small) {
                    routeMarker(symbolName: style.symbolName, tint: style.tint)
                    Text(entry.region.localizedName)
                        .font(stylesheet.homeWidget.rowNameFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(style.emoji)
                        .font(stylesheet.homeWidget.charmFont)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .accessibilityHidden(true)
                    Spacer(minLength: stylesheet.spacing.small)
                    Text(entry.days, format: .number)
                        .font(stylesheet.homeWidget.totalNumberFont)
                        .monospacedDigit()
                        .foregroundStyle(style.tint)
                }
                .padding(.bottom, stylesheet.spacing.xxSmall)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(style.tint.opacity(0.16))
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func routeMarker(symbolName: String, tint: Color) -> some View {
        let style = stylesheet.homeWidget
        return Image(systemName: symbolName)
            .font(.system(size: style.routeSymbolPointSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: style.routeMarkerSize, height: style.routeMarkerSize)
            .background(tint.opacity(0.08), in: .circle)
            .overlay {
                Circle()
                    .stroke(tint.opacity(0.24), lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Image(systemSymbol: .calendarBadgeExclamationmark)
                .font(.title3)
                .foregroundStyle(stylesheet.palette.brand.mineral)
                .accessibilityHidden(true)
            Text(String(localized: .widgetYearEmpty))
                .font(stylesheet.homeWidget.rowNameFont)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    extension YearTotalsWidgetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Ranked",
                configurations: .componentDefaults + SnapshotConfiguration.combinations(
                    layoutDirections: [.rightToLeft],
                ),
                settle: .immediate,
            ) {
                YearTotalsWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california],
                    totals: [
                        .california: 132,
                        .newYork: 41,
                        .canada: 9,
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
            whereSnapshot(
                name: "Glass",
                theme: .glass,
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                YearTotalsWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(theme: .glass))
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
