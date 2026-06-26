import StuffCore
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

    private var regions: [Region] {
        snapshot.orderedDayRegions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.small) {
            HStack(alignment: .firstTextBaseline) {
                Text.localized(LocalizedStrings.Widget.todayTitle)
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
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xSmall) {
            Text(region.style.emoji)
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(region.localizedName)
                .font(.system(.headline, design: .serif).weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(region.style.tint)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
    }

    /// A multi-region day (e.g. a CA→NY flight) lists each region compactly.
    private var regionList: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xSmall) {
            ForEach(regions, id: \.self) { region in
                HStack(spacing: UIConstants.Spacings.small) {
                    Text(region.style.emoji)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(region.localizedName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(region.style.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xSmall) {
            Image(systemName: "location.slash")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text.localized(LocalizedStrings.Widget.todayEmpty)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Single region") {
        TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot())
            .padding()
    }

    #Preview("Multi region") {
        TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
            dayRegions: [.california, .newYork],
            totals: [.california: 132, .newYork: 41],
        ))
        .padding()
    }

    #Preview("Empty") {
        TodayWidgetView(snapshot: PreviewSupport.sampleWidgetSnapshot(
            dayRegions: [],
            totals: [:],
        ))
        .padding()
    }
#endif
