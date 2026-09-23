#if DEBUG
    import SwiftUI

    /// The native registered content that the web exporter sends to the host.
    struct FlyoverExportContent: View {
        let navigationContainer: FlyoverNavigationContainer
        let content: AnyView

        var body: some View {
            Group {
                switch navigationContainer {
                    case .stack:
                        NavigationStack {
                            content
                        }
                    case .none:
                        content
                }
            }
            .allowsHitTesting(false)
        }
    }
#endif
