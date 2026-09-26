import SwiftUI

/// An explicit gallery action that respects the destination's demo availability.
struct FeatureSettingsLink: View {
    let destination: SettingsDestination
    @Environment(\.isInDemoMode) private var isInDemoMode

    var body: some View {
        if !isInDemoMode || destination.isAvailableInDemoMode {
            FeatureMarketingPanel {
                NavigationLink(value: SettingsRoute(destination)) {
                    Label(destination.rowTitle, systemSymbol: destination.systemSymbol)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { FeatureSettingsLink(destination: .devices) }
            .whereBroadwayRoot()
    }
#endif
