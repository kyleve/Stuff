import SwiftUI

/// A miniature Spotlight result showing how an indexed tracked region opens
/// its Where day-count query.
struct FeatureSpotlightPreview: View {
    let example: FeatureDiscoveryPresentation.SpotlightExample

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.featureDiscovery.cardSpacing) {
                Label(
                    String(localized: .settingsExploreSpotlightTitle),
                    systemImage: "magnifyingglass",
                )
                .font(.headline)

                Label {
                    Text(example.query)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, stylesheet.spacing.medium)
                .padding(.vertical, stylesheet.spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: .capsule)

                HStack(spacing: stylesheet.spacing.medium) {
                    AppIconImage(name: "AppIconClassic", size: 44)

                    VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                        Text(example.resultTitle)
                            .font(.headline)
                        Text(example.resultSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: stylesheet.spacing.small)

                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: .settingsExploreSpotlightPreviewLabel(
            example.query,
            example.resultTitle,
            example.resultSubtitle,
        )))
    }
}

#if DEBUG
    #Preview {
        FeatureSpotlightPreview(
            example: .init(
                query: "California",
                resultTitle: "Days in California",
                resultSubtitle: "132 days in 2026",
            ),
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
