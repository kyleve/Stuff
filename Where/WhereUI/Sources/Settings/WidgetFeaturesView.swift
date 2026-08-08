import SnapshotKit
import SwiftUI
import WhereCore

/// A visual catalog of every widget family Where currently offers, grouped on
/// the system surface where the user can add it.
struct WidgetFeaturesView: View {
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    Text(introduction)
                        .foregroundStyle(.secondary)
                }

                Section {
                    FeatureHomeScreenPreview(snapshot: presentation.widgetSnapshot)
                        .listRowInsets(.init())
                        .settingsRow(Item.homeScreen)
                } header: {
                    Text(String(localized: .settingsExploreWidgetsHomeHeader))
                } footer: {
                    Text(String(localized: .settingsExploreWidgetsHomeFooter))
                }

                Section {
                    FeatureLockScreenPreview(
                        date: presentation.lockScreenDate,
                        snapshot: presentation.widgetSnapshot,
                    )
                    .listRowInsets(.init())
                    .settingsRow(Item.lockScreen)
                } header: {
                    Text(String(localized: .settingsExploreWidgetsLockHeader))
                } footer: {
                    Text(String(localized: .settingsExploreWidgetsLockFooter))
                }
            }
        }
        .navigationTitle(String(localized: .settingsExploreWidgetsTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introduction: String {
        presentation.usesUserData
            ? String(localized: .settingsExploreWidgetsPersonalizedIntroduction)
            : String(localized: .settingsExploreWidgetsIntroduction)
    }
}

extension WidgetFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .widgets
    }

    enum Item: SettingsItem {
        case homeScreen
        case lockScreen

        var title: String {
            switch self {
                case .homeScreen: String(localized: .settingsExploreWidgetsHomeHeader)
                case .lockScreen: String(localized: .settingsExploreWidgetsLockHeader)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsWidgets))
        }
    }
}

#if DEBUG
    extension WidgetFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .fullContentScreenDefaults) {
                WidgetFeaturesView(
                    focus: nil,
                    presentation: PreviewSupport.featureDiscoveryPresentation(),
                )
            }
        }
    }

    #Preview {
        NavigationStack {
            WidgetFeaturesView(
                focus: nil,
                presentation: PreviewSupport.featureDiscoveryPresentation(),
            )
        }
        .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension WidgetFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            WidgetFeaturesView.self,
            title: "Widgets",
        )
    }
#endif
