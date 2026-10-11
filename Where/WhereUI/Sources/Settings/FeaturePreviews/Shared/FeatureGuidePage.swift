import SwiftUI

/// Common gallery chrome. Pass a small nominal view as content; constructing
/// rows here stores their combined value in both enclosing scopes.
struct FeatureGuidePage<Content: View>: View {
    let destination: SettingsDestination
    let tagline: LocalizedStringResource
    let focus: SettingsFocus?
    @ViewBuilder let content: Content

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                FeatureGuideForm(destination: destination, tagline: tagline) {
                    content
                }
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
