import SFSafeSymbols
import SwiftUI
import WhereCore

/// Builds gallery rows below the page's reveal and focus scopes so those scopes
/// store only this small view, rather than the complete concrete row tree.
struct PrivacyBackupsFeaturesContent: View {
    let configuration: DiagnosticReportingConfiguration

    var body: some View {
        FeatureGuideExplanationRow(
            title: .settingsExplorePrivacyBackupsPrivacyTitle,
            detail: .settingsExplorePrivacyBackupsPrivacyDetail,
            symbol: .lockShieldFill,
            item: PrivacyBackupsFeaturesView.Item.privacy,
            order: 1,
        )
        PrivacyBackupsPassportRow(configuration: configuration)
        FeatureGuideExplanationRow(
            title: .settingsExplorePrivacyBackupsExportTitle,
            detail: .settingsExplorePrivacyBackupsExportDetail,
            symbol: .externaldriveFill,
            item: PrivacyBackupsFeaturesView.Item.export,
            order: 3,
        )
        FeatureGuideExplanationRow(
            title: .settingsExplorePrivacyBackupsRestoreTitle,
            detail: .settingsExplorePrivacyBackupsRestoreDetail,
            symbol: .squareAndArrowDownFill,
            item: PrivacyBackupsFeaturesView.Item.restore,
            order: 4,
        )
        FeatureSettingsLink(destination: .data).featureMarketingRow(order: 5)
        FeatureSettingsLink(destination: .privacyDiagnostics).featureMarketingRow(order: 6)
    }
}

private struct PrivacyBackupsPassportRow: View {
    let configuration: DiagnosticReportingConfiguration

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        PrivacyPassportCard(
            presentation: PrivacyPassportPresentation(configuration: configuration),
            disclosureInteraction: .staticContent,
        )
        .frame(maxWidth: stylesheet.featureDiscovery.marketingPanel.maxWidth)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .featureMarketingRow(order: 2)
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
