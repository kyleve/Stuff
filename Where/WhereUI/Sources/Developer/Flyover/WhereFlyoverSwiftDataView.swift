#if DEBUG
    import SwiftDataInspector
    import SwiftUI

    /// The generic SwiftData inspector pointed only at Flyover's demo container.
    struct WhereFlyoverSwiftDataView: View {
        let world: WhereFlyoverWorld

        var body: some View {
            if let configuration = world.session.swiftDataInspectorConfiguration {
                NavigationStack {
                    SwiftDataInspectorView(configuration: configuration)
                }
            } else {
                ContentUnavailableView("No model container", systemImage: "cylinder.split.1x2")
            }
        }
    }

    extension WhereFlyoverSwiftDataView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            WhereFlyoverSwiftDataView.self,
            title: "SwiftData Inspector",
            navigationContainer: .none,
        ) { world in
            WhereFlyoverSwiftDataView(world: world)
        }
    }

    #Preview {
        WhereFlyoverSwiftDataView(world: .preview())
    }
#endif
