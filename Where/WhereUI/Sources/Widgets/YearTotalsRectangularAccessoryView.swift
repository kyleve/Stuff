import SnapshotKit
import SwiftUI
import WhereCore

/// Lock-screen rectangular accessory: up to three ranked region day counts,
/// one per line. Same ranking as the home-screen widget, compressed to the
/// rectangular slot's three monochrome lines.
public struct YearTotalsRectangularAccessoryView: View {
    /// The rectangular slot fits three text lines.
    private static let maxRows = 3

    private let snapshot: WidgetSnapshot

    public init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var ranked: [RegionDays] {
        snapshot.rankedTotals(maxRows: Self.maxRows)
    }

    public var body: some View {
        if ranked.isEmpty {
            Label(
                String(localized: .widgetYearEmpty),
                systemImage: "calendar.badge.exclamationmark",
            )
            .font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ranked) { entry in
                    HStack(spacing: stylesheet.spacing.xSmall) {
                        Image(systemName: regionStyles.style(for: entry.region).symbolName)
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(entry.region.localizedName)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: stylesheet.spacing.xSmall)
                        Text(entry.days, format: .number)
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        WhereFormat.regionDaysAccessibility(
                            region: entry.region.localizedName,
                            days: entry.days,
                        ),
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
    extension YearTotalsRectangularAccessoryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Ranked", configurations: .componentLightDark, settle: .immediate) {
                YearTotalsRectangularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [.california],
                    totals: [.california: 132, .newYork: 41, .canada: 9, .other: 2],
                ))
            }
            whereSnapshot(name: "Empty", configurations: .componentLightDark, settle: .immediate) {
                YearTotalsRectangularAccessoryView(snapshot: PreviewSupport.sampleWidgetSnapshot(
                    dayRegions: [],
                    totals: [:],
                ))
            }
        }
    }

    #Preview {
        YearTotalsRectangularAccessoryView.snapshotPreviews
    }
#endif
