import RegionKit
import SnapshotKit
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

    @Environment(\.regionStyles) private var regionStyles

    private var regions: [Region] {
        snapshot.orderedDayRegions
    }

    public var body: some View {
        if let first = regions.first {
            Label(
                regions.map(\.localizedName).joined(separator: " · "),
                systemImage: regionStyles.style(for: first).symbolName,
            )
        } else {
            Label(Strings.widgetTodayEmpty, systemImage: "location.slash")
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

    @Environment(\.regionStyles) private var regionStyles

    private var regions: [Region] {
        snapshot.orderedDayRegions
    }

    public var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(
                    systemName: regions.first
                        .map { regionStyles.style(for: $0).symbolName } ?? "location.slash",
                )
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
        guard !regions.isEmpty else { return Strings.widgetTodayEmpty }
        return regions.map(\.localizedName).joined(separator: ", ")
    }
}

#if DEBUG
    extension TodayInlineAccessoryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Regions",
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                TodayInlineAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california, .newYork],
                    totals: [.california: 132, .newYork: 41],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark, settle: .immediate) {
                TodayInlineAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [],
                    totals: [:],
                ))
            }
        }
    }

    extension TodayCircularAccessoryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Regions",
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                TodayCircularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california, .newYork],
                    totals: [.california: 132, .newYork: 41],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark, settle: .immediate) {
                TodayCircularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [],
                    totals: [:],
                ))
            }
        }
    }

    #Preview("Inline") {
        TodayInlineAccessoryView.snapshotPreviews
    }

    #Preview("Circular") {
        TodayCircularAccessoryView.snapshotPreviews
    }
#endif
