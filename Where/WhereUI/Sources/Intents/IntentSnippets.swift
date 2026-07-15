import RegionKit
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

/// A compact "days in a region" card for Siri / Spotlight / Shortcuts snippets:
/// the region's emoji, the day count, and a "days in <region> · <year>" caption
/// in the region's tint. Presentation only — the App Intents layer feeds it a
/// `DaysInRegionSnapshot`.
public struct DaysInRegionSnippetView: View {
    private let snapshot: DaysInRegionSnapshot

    public init(snapshot: DaysInRegionSnapshot) {
        self.snapshot = snapshot
    }

    @Environment(\.stylesheet) private var stylesheet

    private var region: Region {
        snapshot.region
    }

    public var body: some View {
        HStack(spacing: stylesheet.spacing.medium) {
            Text(region.style.emoji)
                // Semantic Dynamic Type face, matching TodayWidgetView's hero
                // emoji — no hardcoded point size.
                .font(.largeTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                Text(snapshot.dayCount, format: .number)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(region.style.tint)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(stylesheet.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let unit = Strings.dayUnit(snapshot.dayCount)
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

    public var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.secondary)
            if regions.isEmpty {
                emptyState
            } else {
                chips
            }
        }
        .padding(stylesheet.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            ForEach(regions, id: \.self) { region in
                HStack(spacing: stylesheet.spacing.small) {
                    Text(region.style.emoji)
                        .accessibilityHidden(true)
                    Text(region.localizedName)
                        .font(.headline)
                        .foregroundStyle(region.style.tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        HStack(spacing: stylesheet.spacing.small) {
            Image(systemName: "location.slash")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(Strings.widgetTodayEmpty)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

extension RegionsSnippetView {
    /// The "today's regions" snippet — titled with the shared widget "Today"
    /// string.
    public static func today(regions: [Region]) -> RegionsSnippetView {
        RegionsSnippetView(title: Strings.widgetTodayTitle, regions: regions)
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
            Button("Log today here") {}
                .buttonStyle(.borderedProminent)
                .tint(Region.california.style.tint)
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
