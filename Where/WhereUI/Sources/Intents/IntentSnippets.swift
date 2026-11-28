import RegionKit
import SFSafeSymbols
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

    public var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            RegionsSnippetTitle(title: title)
            if regions.isEmpty {
                RegionsSnippetEmptyState()
            } else {
                RegionsSnippetList(regions: regions)
            }
        }
        .padding(stylesheet.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct RegionsSnippetRow: View {
    let region: Region

    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = regionStyles.style(for: region)
        HStack(spacing: stylesheet.spacing.small) {
            Text(style.emoji)
                .accessibilityHidden(true)
            Text(region.localizedName)
                .font(.headline)
                .foregroundStyle(style.tint)
        }
    }
}

private struct RegionsSnippetList: View {
    let regions: [Region]

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            ForEach(regions, id: \.self) { region in
                RegionsSnippetRow(region: region)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RegionsSnippetEmptyState: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.small) {
            Image(systemSymbol: .locationSlash)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(String(localized: .widgetTodayEmpty))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RegionsSnippetTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview("Days in region · with action") { DaysInRegionSnippetCardPreview() }

    private struct DaysInRegionSnippetCardPreview: View {
        var body: some View {
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
