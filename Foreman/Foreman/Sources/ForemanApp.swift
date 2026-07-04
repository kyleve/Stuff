import AppKit
import SwiftUI

@main
struct ForemanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(session: appDelegate.session)
        } label: {
            MenuBarIcon(session: appDelegate.session)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status item image: filled while any worker is live so the menu bar
/// shows at a glance that agents are available.
private struct MenuBarIcon: View {
    let session: ForemanSession

    var body: some View {
        Image(systemName: session.isAnyWorkerLive ? "hammer.fill" : "hammer")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = ForemanSession()

    func applicationDidFinishLaunching(_: Notification) {
        session.start()
    }

    /// Stop-on-quit lifecycle: Foreman owns its worker processes, so quitting
    /// the app tears them all down rather than leaving orphans.
    func applicationWillTerminate(_: Notification) {
        session.stopAllWorkers()
    }
}
