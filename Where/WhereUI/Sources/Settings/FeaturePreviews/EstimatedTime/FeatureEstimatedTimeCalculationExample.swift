import SwiftUI

/// A concrete, fixed-year example that makes the forecast's three inputs and
/// arithmetic visible without fabricating a forecast from the user's data.
struct FeatureEstimatedTimeCalculationExample: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery.estimatedTime

        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.spacing.large) {
                Text(String(localized: .settingsExploreEstimatedTimeCalculationTitle))
                    .font(.headline)

                Text(String(localized: .settingsExploreEstimatedTimeCalculationIntro))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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

                VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                    Label {
                        Text(String(
                            localized: .settingsExploreEstimatedTimeCalculationElapsed,
                        ))
                    } icon: {
                        Circle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: style.legendDotSize, height: style.legendDotSize)
                    }
                    Label {
                        Text(String(
                            localized: .settingsExploreEstimatedTimeCalculationPlanned,
                        ))
                    } icon: {
                        Circle()
                            .fill(.blue)
                            .frame(width: style.legendDotSize, height: style.legendDotSize)
                    }
                    Label {
                        Text(String(
                            localized: .settingsExploreEstimatedTimeCalculationRemaining,
                        ))
                    } icon: {
                        Circle()
                            .fill(.blue.opacity(0.24))
                            .frame(width: style.legendDotSize, height: style.legendDotSize)
                    }
                }
                .font(.footnote)

                Divider()

                VStack(alignment: .leading, spacing: style.calculationSpacing) {
                    Text(String(localized: .settingsExploreEstimatedTimeCalculationPace))
                    Text(String(localized: .settingsExploreEstimatedTimeCalculationProjection))
                    Text(String(localized: .settingsExploreEstimatedTimeCalculationResult))
                        .bold()
                }
                .font(.subheadline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

                Text(String(localized: .settingsExploreEstimatedTimeCalculationOtherRegions))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    #Preview {
        FeatureEstimatedTimeCalculationExample()
            .padding()
            .whereBroadwayRoot()
    }
#endif
