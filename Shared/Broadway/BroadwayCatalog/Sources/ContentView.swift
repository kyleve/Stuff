import BroadwayUI
import SFSafeSymbols
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
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
}

#Preview {
    ContentView()
}
