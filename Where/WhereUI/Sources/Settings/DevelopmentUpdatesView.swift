import InstallerKit
#if DEBUG
    import Flyover
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
            // InstallerKitUI owns the scenario matrix; these check Where branding and integration.
            snapshot(scenario: .available, configurations: [
                .init(device: .iPhoneFullContent),
                .init(colorScheme: .dark, device: .iPhoneFullContent),
                .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
                .init(device: .iPhoneFullContent, snapshotType: .accessibility),
                .init(device: .iPadFullContent),
            ])
            snapshot(scenario: .local, configurations: [.init(device: .iPhoneFullContent)])
        }

        /// Preserve all browsing states independently of the smaller recorded integration matrix.
        enum PreviewScenarios: SnapshotProviding {
            static var snapshots: [SnapshotCase] {
                for scenario in InstallerPreview.Scenario.allCases {
                    DevelopmentUpdatesView.snapshot(
                        scenario: scenario,
                        configurations: scenario == .available ? .fullContentScreenRepresentative :
                            .fullContentPhoneLightDark,
                    )
                }
            }
        }

        private static func snapshot(
            scenario: InstallerPreview.Scenario,
            configurations: [SnapshotConfiguration],
        ) -> SnapshotCase {
            let model = InstallerPreview.model(scenario)
            return whereSnapshot(
                name: scenario.rawValue,
                configurations: configurations,
                measurementReadiness: scenario.requiresRefresh ? .sameAsCapture : .immediate,
                onReadyToMeasure: {
                    if scenario.requiresRefresh { await model.refresh(force: true) }
                },
            ) {
                NavigationStack { DevelopmentUpdatesView(model: model, focus: nil) }
            }
        }
    }

    #Preview { DevelopmentUpdatesView.PreviewScenarios.snapshotPreviews }

    extension DevelopmentUpdatesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(DevelopmentUpdatesView.self) { id, _ in
            FlyoverScreen(
                id: id,
                title: "App Updates",
                variants: PreviewScenarios.snapshots.flatMap { snapshotCase in
                    FlyoverVariant.snapshots(
                        id: FlyoverVariantID(snapshotCase.name),
                        snapshotCase: snapshotCase,
                    )
                },
            )
        }
    }
#endif
