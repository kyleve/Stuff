import RegionKit
import SwiftUI
import WhereCore
import WidgetKit

/// Lock-screen inline accessory (the single line above the clock): today's
/// region name(s) behind the first region's symbol. The slot renders
/// monochrome and truncates aggressively, so this stays a bare `Label`.
public struct TodayInlineAccessoryView: View {
    private let snapshot: WidgetSnapshot

    public init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    private var regions: [Region] {
        snapshot.orderedDayRegions
    }

    public var body: some View {
        if let first = regions.first {
            Label(
                regions.map(\.localizedName).joined(separator: " · "),
                systemImage: first.style.symbolName,
            )
        } else {
            Label(.widgetTodayEmpty, systemImage: "location.slash")
        }
    }
}

/// Lock-screen circular accessory: the symbol of today's region, with a
/// "+n" beneath it when the day spans several regions. Glyph-only because
/// region names can't fit a circle.
public struct TodayCircularAccessoryView: View {
    private let snapshot: WidgetSnapshot

    public init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    private var regions: [Region] {
        snapshot.orderedDayRegions
    }

    public var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: regions.first?.style.symbolName ?? "location.slash")
                    .font(.title3)
                if regions.count > 1 {
                    Text(verbatim: "+\(regions.count - 1)")
                        .font(.caption2.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard !regions.isEmpty else { return String(localized: .widgetTodayEmpty) }
        return regions.map(\.localizedName).joined(separator: ", ")
    }
}

#if DEBUG
    #Preview("Inline", traits: .fixedLayout(width: 200, height: 30)) {
        TodayInlineAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
            dayRegions: [.california, .newYork],
            totals: [.california: 132, .newYork: 41],
        ))
    }

    #Preview("Circular", traits: .fixedLayout(width: 80, height: 80)) {
        TodayCircularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
            dayRegions: [.california, .newYork],
            totals: [.california: 132, .newYork: 41],
        ))
    }
#endif
