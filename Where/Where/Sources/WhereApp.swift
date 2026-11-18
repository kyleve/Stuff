import SwiftUI
import WhereUI

@main
struct WhereApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            appDelegate.runtime.makeRootView()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            appDelegate.runtime.sceneActivityChanged(isActive: phase == .active)
        }
    }
}
