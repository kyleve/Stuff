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

    #Preview {
        WhereFlyoverSwiftDataView(world: .preview())
    }
#endif
