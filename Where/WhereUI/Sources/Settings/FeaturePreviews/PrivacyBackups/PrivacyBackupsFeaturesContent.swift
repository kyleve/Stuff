import SFSafeSymbols
import SwiftUI
import WhereCore

/// Builds gallery rows below the page's reveal and focus scopes so those scopes
/// store only this small view, rather than the complete concrete row tree.
struct PrivacyBackupsFeaturesContent: View {
    let configuration: DiagnosticReportingConfiguration

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        FeatureGuidePanel(
            title: .settingsExplorePrivacyBackupsPrivacyTitle,
            detail: .settingsExplorePrivacyBackupsPrivacyDetail,
            symbol: .lockShieldFill,
        ) {}
            .featureMarketingRow(order: 1)
            .settingsRow(PrivacyBackupsFeaturesView.Item.privacy, restingBackground: .clear)
        PrivacyPassportCard(
            presentation: PrivacyPassportPresentation(configuration: configuration),
            disclosureInteraction: .staticContent,
        )
        .frame(maxWidth: stylesheet.featureDiscovery.marketingPanel.maxWidth)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .featureMarketingRow(order: 2)
        FeatureGuidePanel(
            title: .settingsExplorePrivacyBackupsExportTitle,
            detail: .settingsExplorePrivacyBackupsExportDetail,
            symbol: .externaldriveFill,
        ) {}
            .featureMarketingRow(order: 3)
            .settingsRow(PrivacyBackupsFeaturesView.Item.export, restingBackground: .clear)
        FeatureGuidePanel(
            title: .settingsExplorePrivacyBackupsRestoreTitle,
            detail: .settingsExplorePrivacyBackupsRestoreDetail,
            symbol: .squareAndArrowDownFill,
        ) {}
            .featureMarketingRow(order: 4)
            .settingsRow(PrivacyBackupsFeaturesView.Item.restore, restingBackground: .clear)
        FeatureSettingsLink(destination: .data).featureMarketingRow(order: 5)
        FeatureSettingsLink(destination: .privacyDiagnostics).featureMarketingRow(order: 6)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            PrivacyBackupsFeaturesView(configuration: .defaults(isDebugBuild: false), focus: nil)
        }
        .whereBroadwayRoot()
    }
#endif
