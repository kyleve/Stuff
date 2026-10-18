import InstallerKit
#if DEBUG
    @_spi(Testing) import InstallerKitUI
#else
    import InstallerKitUI
#endif
import SnapshotKit
import SwiftUI

/// Settings detail for the installed channel, incoming commits, and available build.
struct DevelopmentUpdatesView: View {
    let model: UpdateModel
    let focus: SettingsFocus?
    @Environment(\.primaryAppIconName) private var primaryAppIconName

    var body: some View {
        SettingsFocusScope(focus: focus) {
            AppUpdatesView(
                model: model,
                branding: AppUpdateBranding(
                    name: String(localized: .updatesAppName),
                    subtitle: String(localized: .updatesSubtitle),
                    icon: Image(
                        AppIconCatalog
                            .liveSelectedPreviewImageName(primaryAppIconName: primaryAppIconName),
                        bundle: .module,
                    ),
                ),
                sectionDecoration: { section in
                    let item: Item = switch section {
                        case .check: .check
                        case .changes: .changes
                    }
                    return SettingsRowModifier(
                        focus: SettingsFocus(item),
                        restingBackground: .clear,
                    )
                },
            )
        }
    }
}

extension DevelopmentUpdatesView: SettingsSection {
    static var destination: SettingsDestination {
        .updates
    }

    enum Item: SettingsItem {
        case check
        case changes

        var title: String {
            switch self {
                case .check: String(localized: .updatesCheck)
                case .changes: String(localized: .updatesChanges)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .updatesKeywords))
        }
    }
}

#if DEBUG
    extension DevelopmentUpdatesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in InstallerPreview.Scenario.allCases {
                let model = InstallerPreview.model(scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .available ? .fullContentScreenDefaults :
                        .fullContentPhoneLightDark,
                    measurementReadiness: scenario.isOffline ? .sameAsCapture : .immediate,
                    onReadyToMeasure: {
                        if scenario.isOffline { await model.refresh(force: true) }
                    },
                ) {
                    NavigationStack { DevelopmentUpdatesView(model: model, focus: nil) }
                }
            }
        }
    }

    #Preview { DevelopmentUpdatesView.snapshotPreviews }

    extension DevelopmentUpdatesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            DevelopmentUpdatesView.self,
            title: "App Updates",
        )
    }
#endif
