import SFSafeSymbols
import SwiftUI

/// A miniature system Share sheet that makes Where's extension visible inside
/// the app without pretending the gallery can launch a share with no source.
struct FeatureShareSheetPreview: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                Label(
                    String(localized: .settingsExploreEvidenceShareTitle),
                    systemSymbol: .squareAndArrowUp,
                )
                .font(.headline)

                Group {
                    if stylesheet.featureDiscovery.shareSheet.sourcesLayout == .stacked {
                        VStack(
                            alignment: .leading,
                            spacing: stylesheet.featureDiscovery.shareSheet.sourcesSpacing,
                        ) {
                            shareSource(
                                .airplane,
                                title: String(localized: .settingsExploreEvidenceSourcePass),
                            )
                            shareSource(
                                .docRichtext,
                                title: String(localized: .settingsExploreEvidenceSourceReceipt),
                            )
                            shareSource(
                                .photo,
                                title: String(localized: .settingsExploreEvidenceSourcePhoto),
                            )
                        }
                    } else {
                        HStack(spacing: stylesheet.featureDiscovery.shareSheet.sourcesSpacing) {
                            shareSource(
                                .airplane,
                                title: String(localized: .settingsExploreEvidenceSourcePass),
                            )
                            shareSource(
                                .docRichtext,
                                title: String(localized: .settingsExploreEvidenceSourceReceipt),
                            )
                            shareSource(
                                .photo,
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
                .padding(.horizontal, stylesheet.spacing.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func shareSource(_ systemSymbol: SFSymbol, title: String) -> some View {
        Group {
            if stylesheet.featureDiscovery.shareSheet.sourceLayout == .inline {
                HStack(spacing: stylesheet.spacing.small) {
                    sourceIcon(systemSymbol)
                    sourceTitle(
                        title,
                        alignment: stylesheet.featureDiscovery.shareSheet.titleAlignment,
                    )
                }
            } else {
                VStack(spacing: stylesheet.spacing.small) {
                    sourceIcon(systemSymbol)
                    sourceTitle(
                        title,
                        alignment: stylesheet.featureDiscovery.shareSheet.titleAlignment,
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceIcon(_ systemSymbol: SFSymbol) -> some View {
        Image(systemSymbol: systemSymbol)
            .font(.system(size: 22))
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
