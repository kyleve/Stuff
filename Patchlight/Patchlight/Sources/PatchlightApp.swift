import PatchlightUI
import SwiftUI

@main
struct PatchlightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            appDelegate.runtime.makeRootView()
        }
    }
}
