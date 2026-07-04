import SwiftUI

@main
struct ForemanApp: App {
    var body: some Scene {
        MenuBarExtra("Foreman", systemImage: "hammer") {
            Text("Foreman")
        }
        .menuBarExtraStyle(.window)
    }
}
