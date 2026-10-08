import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
struct SiriFeaturesContent: View {
    let presentation: FeatureDiscoveryPresentation

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.featureDiscovery
        Form {
            FeatureMarketingHeader(
                title: String(localized: .settingsExploreSiriTitle),
                tagline: String(localized: .settingsExploreSiriTagline),
                systemSymbol: SettingsDestination.siri.systemSymbol,
                tint: SettingsDestination.siri.iconColor,
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .staggeredReveal(order: 0)

            Section {
                ForEach(
                    SiriIntentFeature.allCases.enumerated(),
                    id: \.element,
                ) { index, feature in
                    let personalized = presentation.siriExample(for: feature)
                    SiriIntentCard(
                        title: feature.item.title,
                        systemSymbol: feature.systemSymbol,
                        request: personalized?.request ?? feature.request,
                        response: personalized?.response ?? feature.response,
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(
                        top: style.siri.card.rowVerticalInset,
                        leading: 0,
                        bottom: style.siri.card.rowVerticalInset,
                        trailing: 0,
                    ))
                    .listRowSeparator(.hidden)
                    .settingsRow(feature.item, restingBackground: .clear)
                    .staggeredReveal(order: index + 1)
                }
            } footer: {
                Text(String(localized: .settingsExploreSiriFooter))
                    .staggeredReveal(order: SiriIntentFeature.allCases.count + 1)
            }

            Section {
                FeatureSpotlightPreview(example: presentation.spotlightExample)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                    .settingsRow(SiriFeaturesView.Item.spotlight, restingBackground: .clear)
                    .staggeredReveal(order: SiriIntentFeature.allCases.count + 1)
            } footer: {
                VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                    Text(String(localized: .settingsExploreSpotlightFooter))
                    FeatureDiscoveryDataFooter()
                }
                .staggeredReveal(order: SiriIntentFeature.allCases.count + 2)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }
}

#if DEBUG
    #Preview {
        NavigationStack { SiriFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif
