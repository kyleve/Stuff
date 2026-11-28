import SFSafeSymbols
import SwiftUI

@main
struct BroadwayCatalogApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { BroadwayCatalogHome() }
        }
    }
}

private struct BroadwayCatalogHome: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemSymbol: .theatermasksFill)
                .font(.system(size: 64))

            Text("Broadway Catalog")
                .font(.largeTitle.bold())
        }
        .padding()
        .navigationTitle("Broadway Catalog")
    }
}

#if DEBUG
    #Preview { NavigationStack { BroadwayCatalogHome() } }
#endif
