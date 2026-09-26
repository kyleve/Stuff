import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
struct ShareEvidenceFeaturesContent: View {
    let report: YearReportModel
    let presentation: FeatureDiscoveryPresentation
    let archiveContent: FeatureEvidenceArchivePreview.Content

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Form {
            FeatureMarketingHeader(
                title: String(localized: .settingsExploreEvidenceTitle),
                tagline: String(localized: .settingsExploreEvidenceTagline),
                systemSymbol: SettingsDestination.shareEvidence.systemSymbol,
                tint: SettingsDestination.shareEvidence.iconColor,
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .staggeredReveal(order: 0)

            Section {
                FeatureShareSheetPreview()
                    .featureMarketingRow(order: 1)
                    .settingsRow(
                        ShareEvidenceFeaturesView.Item.shareSheet,
                        restingBackground: .clear,
                    )
                FeatureEvidenceComposePreview(date: presentation.lockScreenDate)
                    .featureMarketingRow(order: 2)
                    .settingsRow(ShareEvidenceFeaturesView.Item.compose, restingBackground: .clear)
                FeatureEvidenceArchivePreview(content: archiveContent)
                    .featureMarketingRow(order: 3)
                    .settingsRow(ShareEvidenceFeaturesView.Item.archive, restingBackground: .clear)
                FeatureMarketingPanel {
                    NavigationLink(value: Route.archive) {
                        Label {
                            Text(String(localized: .settingsExploreEvidenceOpenArchive))
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemSymbol: .paperclip)
                                .foregroundStyle(SettingsDestination.shareEvidence
                                    .iconColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .featureMarketingRow(order: 4)
            } footer: {
                VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                    Text(String(localized: .settingsExploreEvidenceFooter))
                    FeatureDiscoveryDataFooter()
                }
                .staggeredReveal(order: 5)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
        .navigationDestination(for: Route.self) { route in
            switch route {
                case .archive: EvidenceListView(report: report)
            }
        }
    }

    private enum Route: Hashable {
        case archive
    }
}

#if DEBUG
    #Preview {
        NavigationStack { ShareEvidenceFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif
