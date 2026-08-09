import SwiftUI

/// A miniature system Share sheet that makes Where's extension visible inside
/// the app without pretending the gallery can launch a share with no source.
struct FeatureShareSheetPreview: View {
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.featureDiscovery.cardSpacing) {
                Label(
                    String(localized: .settingsExploreEvidenceShareTitle),
                    systemImage: "square.and.arrow.up",
                )
                .font(.headline)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            shareSource(
                                "airplane",
                                title: String(localized: .settingsExploreEvidenceSourcePass),
                            )
                            shareSource(
                                "doc.richtext",
                                title: String(localized: .settingsExploreEvidenceSourceReceipt),
                            )
                            shareSource(
                                "photo",
                                title: String(localized: .settingsExploreEvidenceSourcePhoto),
                            )
                        }
                    } else {
                        HStack(spacing: stylesheet.spacing.large) {
                            shareSource(
                                "airplane",
                                title: String(localized: .settingsExploreEvidenceSourcePass),
                            )
                            shareSource(
                                "doc.richtext",
                                title: String(localized: .settingsExploreEvidenceSourceReceipt),
                            )
                            shareSource(
                                "photo",
                                title: String(localized: .settingsExploreEvidenceSourcePhoto),
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                Label {
                    VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                        Text(String(localized: .settingsExploreEvidenceShareAction))
                            .font(.headline)
                        Text(String(localized: .settingsExploreEvidenceShareActionSubtitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    AppIconImage(name: "AppIconClassic", size: 44)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func shareSource(_ systemImage: String, title: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: stylesheet.spacing.small) {
                    sourceIcon(systemImage)
                    sourceTitle(title, alignment: .leading)
                }
            } else {
                VStack(spacing: stylesheet.spacing.small) {
                    sourceIcon(systemImage)
                    sourceTitle(title, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .frame(width: 44, height: 44)
            .background(.quaternary, in: .rect(cornerRadius: 12))
    }

    private func sourceTitle(_ title: String, alignment: TextAlignment) -> some View {
        Text(title)
            .font(.caption)
            .multilineTextAlignment(alignment)
    }
}

#if DEBUG
    #Preview {
        FeatureShareSheetPreview()
            .padding()
            .whereBroadwayRoot()
    }
#endif
