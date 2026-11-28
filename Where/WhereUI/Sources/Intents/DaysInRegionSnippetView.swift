import RegionKit
import SwiftUI

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
    @Environment(\.regionStyles) private var regionStyles

    private var region: Region {
        snapshot.region
    }

    public var body: some View {
        let style = regionStyles.style(for: region)
        return HStack(spacing: stylesheet.spacing.medium) {
            Text(style.emoji)
                // Semantic Dynamic Type face, matching TodayWidgetView's hero
                // emoji — no hardcoded point size.
                .font(.largeTitle)
                .accessibilityHidden(true)
            DaysInRegionSnippetCount(snapshot: snapshot, tint: style.tint)
            Spacer(minLength: 0)
        }
        .padding(stylesheet.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct DaysInRegionSnippetCount: View {
    let snapshot: DaysInRegionSnapshot
    let tint: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Text(snapshot.dayCount, format: .number)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var caption: String {
        let unit = WhereFormat.dayUnit(snapshot.dayCount)
        let yearText = snapshot.year.formatted(.number.grouping(.never))
        return "\(unit) in \(snapshot.region.localizedName) · \(yearText)"
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
            snapshot: DaysInRegionSnapshot(region: .ontario, year: 2026, dayCount: 1),
        )
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
#endif
