import SwiftUI
import WhereUI

@main
struct WhereApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            appDelegate.runtime.makeRootView()
        }
    }
}
