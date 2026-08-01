import SwiftUI

/// One symbol-plus-title item in the heatmap legend.
struct YearHeatmapLegendLabel: View {
    let title: String
    let symbol: String
    let color: Color

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.medium) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        YearHeatmapLegendLabel(
            title: "California",
            symbol: "sun.max.fill",
            color: .orange,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
