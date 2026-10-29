#if DEBUG
    import SwiftUI

    /// Injects the isolated Flyover world and Where's style root around app content.
    struct WhereFlyoverHost<Content: View>: View {
        let world: WhereFlyoverWorld
        @ViewBuilder let content: Content

        var body: some View {
            content
                .whereEnvironment(.isolated(model: world.model, session: world.session))
        }
    }

    #Preview {
        WhereFlyoverHost(world: .preview()) {
            Text("Flyover content")
        }
    }
#endif
