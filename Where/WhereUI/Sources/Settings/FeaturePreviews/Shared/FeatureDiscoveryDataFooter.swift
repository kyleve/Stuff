import SwiftUI

/// The universal disclosure beneath every feature-marketing gallery.
struct FeatureDiscoveryDataFooter: View {
    var body: some View {
        Text(String(localized: .settingsExploreDataFooter))
    }
}

#if DEBUG
    #Preview {
        FeatureDiscoveryDataFooter()
            .padding()
    }
#endif
