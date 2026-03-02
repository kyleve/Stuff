import SwiftUI
import BroadwayUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "theatermasks.fill")
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
