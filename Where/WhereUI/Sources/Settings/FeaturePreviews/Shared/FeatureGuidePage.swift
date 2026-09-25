import SwiftUI

/// Common gallery chrome. Content stays in each screen's own small view.
struct FeatureGuidePage<Content: View>: View {
    let destination: SettingsDestination
    let tagline: LocalizedStringResource
    let focus: SettingsFocus?
    @ViewBuilder let content: Content

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            FeatureGuidePage(
                destination: .placesYear,
                tagline: .settingsExplorePlacesTagline,
                focus: nil,
            ) {
                Text(.settingsExplorePlacesLocationsTitle)
            }
        }
        .whereBroadwayRoot()
    }
#endif
