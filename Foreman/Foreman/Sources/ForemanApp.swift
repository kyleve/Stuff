import AppKit
import ForemanCore
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

    // Same observation workaround as MenuContentView (see its
    // startPumpIfNeeded): the status-item label is another hierarchy
    // MenuBarExtra hosts once at launch, so without the pump the icon would
    // freeze on its launch-time state.
    @State private var refreshTick = 0
    @State private var pump: ObservationPump?

    var body: some View {
        let _ = refreshTick
        Image(systemName: session.isAnyWorkerLive ? "hammer.fill" : "hammer")
            .onAppear {
                guard pump == nil else { return }
                pump = ObservationPump(
                    tracking: { _ = session.isAnyWorkerLive },
                    onChange: { refreshTick += 1 },
                )
            }
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
