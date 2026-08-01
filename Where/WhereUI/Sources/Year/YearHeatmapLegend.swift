import RegionKit
import SwiftUI

/// The non-color legend for heatmap regions and special day states.
struct YearHeatmapLegend: View {
    let overview: YearOverview

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var style: WhereStylesheet.YearOverviewStyle {
        stylesheet.yearOverview
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: style.heatmap.legendSpacing,
        ) {
            ForEach(overview.regions, id: \.self) { region in
                YearHeatmapLegendLabel(
                    title: region.localizedName,
                    symbol: regionStyles.style(for: region).symbolName,
                    color: regionStyles.style(for: region).tint,
                )
            }
            if hasSlice(.unrecorded) {
                YearHeatmapLegendLabel(
                    title: String(localized: .yearOverviewUnrecorded),
                    symbol: "exclamationmark.circle.fill",
                    color: style.unrecordedColor,
                )
            }
            if hasSlice(.remaining) {
                YearHeatmapLegendLabel(
                    title: String(localized: .yearOverviewRemaining),
                    symbol: "clock.fill",
                    color: style.remainingColor,
                )
            }
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), alignment: .leading)]
        }
        return [GridItem(
            .adaptive(minimum: style.heatmap.legendMinItemWidth),
            alignment: .leading,
        )]
    }

    private func hasSlice(_ id: YearOverview.Slice.ID) -> Bool {
        overview.slices.contains { $0.id == id }
    }
}

#if DEBUG
    #Preview {
        YearHeatmapLegend(overview: PreviewSupport.loadedYearOverview())
            .padding()
            .whereBroadwayRoot()
    }
#endif
