import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
struct WidgetFeaturesContent: View {
    let presentation: FeatureDiscoveryPresentation

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Form {
            FeatureMarketingHeader(
                title: String(localized: .settingsExploreWidgetsTitle),
                tagline: String(localized: .settingsExploreWidgetsTagline),
                systemSymbol: SettingsDestination.widgets.systemSymbol,
                tint: SettingsDestination.widgets.iconColor,
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .staggeredReveal(order: 0)

            Section {
                FeatureHomeScreenExample(snapshot: presentation.widgetSnapshot)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .settingsRow(WidgetFeaturesView.Item.homeScreen, restingBackground: .clear)
                    .staggeredReveal(order: 1)
            } header: {
                Text(String(localized: .settingsExploreWidgetsHomeHeader))
                    .staggeredReveal(order: 1)
            } footer: {
                Text(String(localized: .settingsExploreWidgetsHomeFooter))
                    .staggeredReveal(order: 1)
            }

            Section {
                FeatureLockScreenExample(
                    date: presentation.lockScreenDate,
                    snapshot: presentation.widgetSnapshot,
                )
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
                .settingsRow(WidgetFeaturesView.Item.lockScreen, restingBackground: .clear)
                .staggeredReveal(order: 2)
            } header: {
                Text(String(localized: .settingsExploreWidgetsLockHeader))
                    .staggeredReveal(order: 2)
            } footer: {
                VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                    Text(String(localized: .settingsExploreWidgetsLockFooter))
                        .staggeredReveal(order: 2)
                    FeatureDiscoveryDataFooter()
                        .staggeredReveal(order: 3)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }
}

#if DEBUG
    #Preview {
        NavigationStack { WidgetFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif
