import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// The value a `DaysInRegionSnippetView` renders: a region, the year, and the
/// day count. A small `Sendable` value so the App Intents layer builds it and
/// the view stays presentation-only and previewable.
public struct DaysInRegionSnapshot: Hashable, Sendable {
    public let region: Region
    public let year: Int
    public let dayCount: Int

    public init(region: Region, year: Int, dayCount: Int) {
        self.region = region
        self.year = year
        self.dayCount = dayCount
    }
}

/// A compact archival record for Siri, Spotlight, and Shortcuts. The region
/// name and tabular count lead, its symbol is the route marker, and the user's
/// emoji remains a small personalization charm.
public struct DaysInRegionSnippetView: View {
    private let snapshot: DaysInRegionSnapshot

    public init(snapshot: DaysInRegionSnapshot) {
        self.snapshot = snapshot
    }

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var region: Region {
        snapshot.region
    }

    public var body: some View {
        let component = stylesheet.recordSnippet
        let regionStyle = regionStyles.style(for: region)
        return VStack(alignment: .leading, spacing: component.contentSpacing) {
            HStack(spacing: stylesheet.spacing.medium) {
                WhereSeal(tint: stylesheet.palette.brand.brass)
                    .frame(width: component.sealSize, height: component.sealSize)

                Text(region.localizedName)
                    .font(component.titleFont)
                    .foregroundStyle(regionStyle.tint)
                    .lineLimit(2)

                Spacer(minLength: 0)

                routeMarker(style: regionStyle)
                Text(regionStyle.emoji)
                    .font(component.charmFont)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityHidden(true)
            }

            Rectangle()
                .fill(regionStyle.tint.opacity(component.ruleOpacity))
                .frame(height: 0.75)
                .accessibilityHidden(true)

            countRecord(tint: regionStyle.tint)
        }
        .modifier(RecordSnippetSurface())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func countRecord(tint: Color) -> some View {
        let component = stylesheet.recordSnippet
        if component.stacksHero {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                count(tint: tint)
                countCaption
            }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: stylesheet.spacing.medium) {
                count(tint: tint)
                countCaption
                Spacer(minLength: 0)
            }
        }
    }

    private func count(tint: Color) -> some View {
        Text(snapshot.dayCount, format: .number)
            .font(stylesheet.recordSnippet.numberFont)
            .foregroundStyle(tint)
            .contentTransition(.numericText())
    }

    private var countCaption: some View {
        Text(caption)
            .font(stylesheet.recordSnippet.captionFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func routeMarker(style: RegionStyle) -> some View {
        let component = stylesheet.recordSnippet
        return Image(systemName: style.symbolName)
            .font(.system(size: component.routeSymbolPointSize, weight: .semibold))
            .foregroundStyle(style.tint)
            .frame(width: component.routeMarkerSize, height: component.routeMarkerSize)
            .background(style.tint.opacity(0.08), in: .circle)
            .overlay {
                Circle()
                    .stroke(style.tint.opacity(0.24), lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }

    private var caption: String {
        let unit = WhereFormat.dayUnit(snapshot.dayCount)
        let yearText = snapshot.year.formatted(.number.grouping(.never))
        return "\(unit) in \(region.localizedName) · \(yearText)"
    }
}

/// The day-count card with a trailing action area — the interactive snippet's
/// layout. Owns the card's spacing and the action's padding via the stylesheet,
/// so the App Intents layer (which supplies the `Button(intent:)` but can't see
/// the internal `WhereStylesheet`) doesn't hardcode geometry.
public struct DaysInRegionSnippetCard<Action: View>: View {
    private let snapshot: DaysInRegionSnapshot
    private let action: Action

    public init(snapshot: DaysInRegionSnapshot, @ViewBuilder action: () -> Action) {
        self.snapshot = snapshot
        self.action = action()
    }

    @Environment(\.stylesheet) private var stylesheet

    public var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            DaysInRegionSnippetView(snapshot: snapshot)
            action
                .padding(.horizontal, stylesheet.spacing.medium)
                .padding(.bottom, stylesheet.spacing.medium)
        }
    }
}

/// A titled list of regions for a snippet card — the shared body behind the
/// "today" and "on a date" snippets. Shows region chips, or a muted empty
/// state when nothing is logged.
public struct RegionsSnippetView: View {
    private let title: String
    private let regions: [Region]

    public init(title: String, regions: [Region]) {
        self.title = title
        self.regions = regions
    }

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    public var body: some View {
        let component = stylesheet.recordSnippet
        VStack(alignment: .leading, spacing: component.contentSpacing) {
            HStack(spacing: stylesheet.spacing.medium) {
                WhereSeal(tint: stylesheet.palette.brand.brass)
                    .frame(width: component.sealSize, height: component.sealSize)
                Text(title)
                    .font(component.titleFont)
                    .foregroundStyle(stylesheet.palette.brand.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(stylesheet.palette.brand.brass.opacity(component.ruleOpacity))
                .frame(height: 0.75)
                .accessibilityHidden(true)

            if regions.isEmpty {
                emptyState
            } else {
                chips
            }
        }
        .modifier(RecordSnippetSurface())
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            ForEach(regions, id: \.self) { region in
                let style = regionStyles.style(for: region)
                HStack(spacing: stylesheet.spacing.small) {
                    routeMarker(style: style)
                    Text(region.localizedName)
                        .font(stylesheet.recordSnippet.titleFont)
                        .foregroundStyle(style.tint)
                        .lineLimit(2)
                    Text(style.emoji)
                        .font(stylesheet.recordSnippet.charmFont)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(region.localizedName)
            }
        }
    }

    private func routeMarker(style: RegionStyle) -> some View {
        let component = stylesheet.recordSnippet
        return Image(systemName: style.symbolName)
            .font(.system(size: component.routeSymbolPointSize, weight: .semibold))
            .foregroundStyle(style.tint)
            .frame(width: component.routeMarkerSize, height: component.routeMarkerSize)
            .background(style.tint.opacity(0.08), in: .circle)
            .overlay {
                Circle()
                    .stroke(style.tint.opacity(0.24), lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }

    private var emptyState: some View {
        HStack(spacing: stylesheet.spacing.small) {
            Image(systemSymbol: .locationSlash)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(String(localized: .widgetTodayEmpty))
                .font(stylesheet.recordSnippet.captionFont)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordSnippetSurface: ViewModifier {
    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet.recordSnippet
        let brand = stylesheet.palette.brand
        content
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(brand.raisedPaper, in: .rect(cornerRadius: style.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .stroke(brand.brass.opacity(style.borderOpacity), lineWidth: 0.75)
            }
    }
}

extension RegionsSnippetView {
    /// The "today's regions" snippet — titled with the shared widget "Today"
    /// string.
    public static func today(regions: [Region]) -> RegionsSnippetView {
        RegionsSnippetView(title: String(localized: .widgetTodayTitle), regions: regions)
    }

    /// The "regions on a date" snippet — titled with the wide-format date.
    public static func onDate(_ date: Date, regions: [Region]) -> RegionsSnippetView {
        RegionsSnippetView(
            title: date.formatted(.dateTime.month(.wide).day().year()),
            regions: regions,
        )
    }
}

#if DEBUG
    extension DaysInRegionSnippetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Recorded",
                configurations: .componentDefaults + SnapshotConfiguration.combinations(
                    layoutDirections: [.rightToLeft],
                ),
                settle: .immediate,
            ) {
                DaysInRegionSnippetView(
                    snapshot: DaysInRegionSnapshot(
                        region: .california,
                        year: PreviewSupport.year,
                        dayCount: 132,
                    ),
                )
            }
        }
    }

    extension RegionsSnippetView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Multiple",
                configurations: .componentDefaults + SnapshotConfiguration.combinations(
                    layoutDirections: [.rightToLeft],
                ),
                settle: .immediate,
            ) {
                RegionsSnippetView.today(regions: [.california, .newYork])
            }
            whereSnapshot(
                name: "Empty",
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                RegionsSnippetView.onDate(PreviewSupport.referenceNow, regions: [])
            }
        }
    }

    #Preview("Days in region") {
        DaysInRegionSnippetView(
            snapshot: DaysInRegionSnapshot(region: .california, year: 2026, dayCount: 132),
        )
        .whereBroadwayRoot()
    }

    #Preview("Days in region · single") {
        DaysInRegionSnippetView(
            snapshot: DaysInRegionSnapshot(region: .canada, year: 2026, dayCount: 1),
        )
        .whereBroadwayRoot()
    }

    #Preview("Days in region · with action") {
        DaysInRegionSnippetCard(
            snapshot: DaysInRegionSnapshot(region: .california, year: 2026, dayCount: 132),
        ) {
            Button(String(localized: .snippetLogTodayHere)) {}
                .buttonStyle(.borderedProminent)
                .tint(RegionStyle.fallbackStyle(for: .california).tint)
                .frame(maxWidth: .infinity)
        }
        .whereBroadwayRoot()
    }

    #Preview("Today · multi") {
        RegionsSnippetView.today(regions: [.california, .newYork])
            .whereBroadwayRoot()
    }

    #Preview("On date · empty") {
        RegionsSnippetView.onDate(.now, regions: [])
            .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension DaysInRegionSnippetView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            DaysInRegionSnippetView.self,
            title: "Days in Region Snippet",
            viewport: .fixed(CGSize(width: 360, height: 150)),
            navigationContainer: .none,
        ) { _ in
            DaysInRegionSnippetView(
                snapshot: DaysInRegionSnapshot(
                    region: .california,
                    year: PreviewSupport.year,
                    dayCount: 132,
                ),
            )
        }
    }

    extension RegionsSnippetView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            RegionsSnippetView.self,
            title: "Regions Snippet",
            viewport: .fixed(CGSize(width: 360, height: 190)),
            navigationContainer: .none,
        ) { _ in
            RegionsSnippetView.today(regions: [.california, .newYork])
        }
    }
#endif
