import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A read-only walkthrough of privacy & backups with explicit actions into existing screens.
struct PrivacyBackupsFeaturesView: View {
    let configuration: DiagnosticReportingConfiguration
    let focus: SettingsFocus?

    var body: some View {
        FeatureGuidePage(
            destination: .privacyBackups,
            tagline: .settingsExplorePrivacyBackupsTagline,
            focus: focus,
        ) {
            FeatureGuidePanel(
                title: .settingsExplorePrivacyBackupsPrivacyTitle,
                detail: .settingsExplorePrivacyBackupsPrivacyDetail,
                symbol: .lockShieldFill,
            ) {}
                .featureMarketingRow(order: 1)
                .settingsRow(Item.privacy, restingBackground: .clear)
            PrivacyPassportCard(
                presentation: PrivacyPassportPresentation(configuration: configuration),
                disclosureInteraction: .staticContent,
            )
            .fixedSize(horizontal: false, vertical: true)
            .featureMarketingRow(order: 2)
            FeatureGuidePanel(
                title: .settingsExplorePrivacyBackupsExportTitle,
                detail: .settingsExplorePrivacyBackupsExportDetail,
                symbol: .externaldriveFill,
            ) {}
                .featureMarketingRow(order: 3)
                .settingsRow(Item.export, restingBackground: .clear)
            FeatureGuidePanel(
                title: .settingsExplorePrivacyBackupsRestoreTitle,
                detail: .settingsExplorePrivacyBackupsRestoreDetail,
                symbol: .squareAndArrowDownFill,
            ) {}
                .featureMarketingRow(order: 4)
                .settingsRow(Item.restore, restingBackground: .clear)
            FeatureSettingsLink(destination: .data).featureMarketingRow(order: 5)
            FeatureSettingsLink(destination: .privacyDiagnostics).featureMarketingRow(order: 6)
        }
    }
}

extension PrivacyBackupsFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .privacyBackups
    }

    enum Item: SettingsItem {
        case privacy
        case export
        case restore

        var title: String {
            switch self {
                case .privacy: String(localized: .settingsExplorePrivacyBackupsPrivacyTitle)
                case .export: String(localized: .settingsExplorePrivacyBackupsExportTitle)
                case .restore: String(localized: .settingsExplorePrivacyBackupsRestoreTitle)
            }
        }

        var keywords: [String] {
            switch self {
                case .privacy: splitKeywords(
                        String(localized: .settingsExplorePrivacyBackupsPrivacyKeywords),
                    )
                case .export: splitKeywords(
                        String(localized: .settingsExplorePrivacyBackupsExportKeywords),
                    )
                case .restore: splitKeywords(
                        String(localized: .settingsExplorePrivacyBackupsRestoreKeywords),
                    )
            }
        }
    }
}

#if DEBUG
    extension PrivacyBackupsFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .fullContentScreenDefaults) {
                PrivacyBackupsFeaturesView(
                    configuration: .defaults(isDebugBuild: false),
                    focus: nil,
                )
            }
            whereSnapshot(name: "DiagnosticsOff", configurations: .fullContentPhoneLightDark) {
                PrivacyBackupsFeaturesView(configuration: DiagnosticReportingConfiguration(
                    sharesCrashReports: false,
                    sharesSessionReplays: false,
                    remoteLogging: .off,
                ), focus: nil)
            }
            whereSnapshot(name: "Demo", configurations: .fullContentPhoneLightDark) {
                PrivacyBackupsFeaturesView(
                    configuration: .defaults(isDebugBuild: false),
                    focus: nil,
                )
                .environment(\.isInDemoMode, true)
            }
        }
    }

    #Preview {
        NavigationStack { PrivacyBackupsFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }

    extension PrivacyBackupsFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            PrivacyBackupsFeaturesView.self,
            title: "Privacy & Backups",
            routes: [
                .push(to: DataSettingsView.flyoverID),
                .push(to: PrivacyDiagnosticsSettingsView.flyoverID),
            ],
        )
    }
#endif
