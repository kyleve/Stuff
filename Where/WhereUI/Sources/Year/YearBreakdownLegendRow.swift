import SwiftUI

/// A breakdown legend item that moves its count below the title when both
/// values cannot remain readable on one line.
struct YearBreakdownLegendRow: View {
    let title: String
    let dayCount: String
    let symbol: String
    let color: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: stylesheet.spacing.large) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(
                        minWidth: stylesheet.yearOverview.breakdown.legendSwatchSize,
                        minHeight: stylesheet.yearOverview.breakdown.legendSwatchSize,
                    )
                    .accessibilityHidden(true)
                Text(title)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: stylesheet.spacing.large)
                Text(dayCount)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(alignment: .top, spacing: stylesheet.spacing.large) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(
                        minWidth: stylesheet.yearOverview.breakdown.legendSwatchSize,
                        minHeight: stylesheet.yearOverview.breakdown.legendSwatchSize,
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                    Text(title)
                    Text(dayCount)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        YearBreakdownLegendRow(
            title: "California",
            dayCount: "148 days",
            symbol: "sun.max.fill",
            color: .orange,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
