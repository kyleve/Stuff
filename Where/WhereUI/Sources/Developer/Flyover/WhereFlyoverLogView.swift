#if DEBUG
    import PeriscopeTools
    import SwiftUI

    /// The demo scope's in-memory log browser, with an honest unavailable state.
    struct WhereFlyoverLogView: View {
        let world: WhereFlyoverWorld

        var body: some View {
            if let store = world.scope.logStore {
                PeriscopeViewer(store: store, title: "Logs")
            } else {
                ContentUnavailableView("No log store", systemImage: "ladybug.slash")
            }
        }
    }

    extension WhereFlyoverLogView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            WhereFlyoverLogView.self,
            title: "Logs",
        ) { world in
            WhereFlyoverLogView(world: world)
        }
    }

    #Preview {
        WhereFlyoverLogView(world: .preview())
    }
#endif
