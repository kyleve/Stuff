import SwiftUI

@main
struct CodeGraphViewerApp: App {
    @State private var store = GraphStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { store.restore() }
        }
    }
}
