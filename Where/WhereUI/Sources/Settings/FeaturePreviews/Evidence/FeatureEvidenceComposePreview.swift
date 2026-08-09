import SwiftUI
import WhereCore

/// A read-only miniature of the compose form the Share extension presents.
struct FeatureEvidenceComposePreview: View {
    let date: Date

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: stylesheet.featureDiscovery.cardSpacing) {
                Label(
                    String(localized: .settingsExploreEvidenceComposeTitle),
                    systemImage: "checkmark.circle",
                )
                .font(.headline)

                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(String(localized: .evidenceFormKind))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(
                        EvidenceKind.boardingPass.displayName,
                        systemImage: EvidenceKind.boardingPass.symbolName,
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
                    systemImage: "paperclip",
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
