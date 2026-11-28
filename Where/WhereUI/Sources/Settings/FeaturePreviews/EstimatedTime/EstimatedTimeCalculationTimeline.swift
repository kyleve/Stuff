import SwiftUI

struct EstimatedTimeCalculationTimeline: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.estimatedTime
        GeometryReader { geometry in
            let segmentWidth = max(
                0,
                geometry.size.width - style.timelineSpacing * 2,
            )

            HStack(spacing: style.timelineSpacing) {
                RoundedRectangle(cornerRadius: style.segmentCornerRadius)
                    .fill(.secondary.opacity(0.35))
                    .frame(width: segmentWidth * 182 / 365)
                RoundedRectangle(cornerRadius: style.segmentCornerRadius)
                    .fill(.blue)
                    .frame(width: segmentWidth * 9 / 365)
                RoundedRectangle(cornerRadius: style.segmentCornerRadius)
                    .fill(.blue.opacity(0.24))
                    .frame(width: segmentWidth * 174 / 365)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(
                localized: .settingsExploreEstimatedTimeCalculationTimeline,
            ))
        }
        .frame(height: style.timelineHeight)
    }
}

#if DEBUG
    #Preview { EstimatedTimeCalculationTimeline().padding().whereBroadwayRoot() }
#endif
