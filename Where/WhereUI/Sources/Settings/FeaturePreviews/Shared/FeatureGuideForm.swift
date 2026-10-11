import SwiftUI

/// Keeps the concrete Form value out of the enclosing reveal and focus scopes.
struct FeatureGuideForm<Content: View>: View {
    let destination: SettingsDestination
    let tagline: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            FeatureMarketingHeader(
                title: destination.rowTitle,
                tagline: String(localized: tagline),
                systemSymbol: destination.systemSymbol,
                tint: destination.iconColor,
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .staggeredReveal(order: 0)
            content
            Section {} footer: { FeatureDiscoveryDataFooter() }
        }
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            FeatureGuideForm(destination: .placesYear, tagline: .settingsExplorePlacesTagline) {
                Text(.settingsExplorePlacesLocationsTitle)
            }
        }
        .whereBroadwayRoot()
    }
#endif
