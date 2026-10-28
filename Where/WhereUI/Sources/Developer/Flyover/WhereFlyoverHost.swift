#if DEBUG
    import SwiftUI

    /// Injects the isolated Flyover world and Where's style root around app content.
    struct WhereFlyoverHost<Content: View>: View {
        let world: WhereFlyoverWorld
        @ViewBuilder let content: Content

        var body: some View {
            content
                .environment(world.model)
                .environment(world.session)
                .environment(\.isInDemoMode, true)
                .whereBroadwayRoot(regionStyles: world.session.regionStyles)
        }
    }

    #Preview {
        WhereFlyoverHost(world: .preview()) {
            Text("Flyover content")
        }
    }
#endif
