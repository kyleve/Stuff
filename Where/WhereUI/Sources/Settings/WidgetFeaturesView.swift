import SnapshotKit
import SwiftUI
import WhereCore

/// A visual catalog of every widget family Where currently offers, grouped on
/// the system surface where the user can add it.
struct WidgetFeaturesView: View {
    let focus: SettingsFocus?

    private let snapshot: WidgetSnapshot

    init(
        focus: SettingsFocus?,
        snapshot: WidgetSnapshot,
    ) {
        self.focus = focus
        self.snapshot = snapshot
    }

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    Text(String(localized: .settingsExploreWidgetsIntroduction))
                        .foregroundStyle(.secondary)
                }

                Section {
                    FeatureHomeScreenPreview(snapshot: snapshot)
                        .listRowInsets(.init())
                        .settingsRow(Item.homeScreen)
                } header: {
                    Text(String(localized: .settingsExploreWidgetsHomeHeader))
                } footer: {
                    Text(String(localized: .settingsExploreWidgetsHomeFooter))
                }

                Section {
                    FeatureLockScreenPreview(snapshot: snapshot)
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
                    snapshot: PreviewSupport.sampleWidgetSnapshot(),
                )
            }
        }
    }

    #Preview {
        NavigationStack {
            WidgetFeaturesView(
                focus: nil,
                snapshot: PreviewSupport.sampleWidgetSnapshot(),
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
