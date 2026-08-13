import SFSafeSymbols
import SwiftUI
import WhereCore

/// A read-only miniature of the compose form the Share extension presents.
struct FeatureEvidenceComposePreview: View {
    let date: Date

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                Label(
                    String(localized: .settingsExploreEvidenceComposeTitle),
                    systemSymbol: .checkmarkCircle,
                )
                .font(.headline)

                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(String(localized: .evidenceFormKind))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(
                        EvidenceKind.boardingPass.displayName,
                        systemSymbol: EvidenceKind.boardingPass.symbol,
                    )
                }
                Divider()
                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(String(localized: .evidenceFormDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(date, format: .dateTime.month(.abbreviated).day().year())
                }
                Divider()
                Label(
                    String(localized: .settingsExploreEvidenceAttachmentReady),
                    systemSymbol: .paperclip,
                )
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
    #Preview {
        FeatureEvidenceComposePreview(date: PreviewSupport.referenceNow)
            .padding()
            .whereBroadwayRoot()
    }
#endif
