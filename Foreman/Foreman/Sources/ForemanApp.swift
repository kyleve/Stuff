import AppKit
import ForemanCore
import SwiftUI

/// Why AppKit (NSStatusItem + NSPopover) instead of MenuBarExtra:
/// MenuBarExtra(.window) builds its content hierarchy once at launch and loses
/// SwiftUI's observation of it — @Observable mutations landing while the panel
/// was closed never rendered, and every "detect the open and force a refresh"
/// hook we tried (onAppear, controlActiveState, key-window and occlusion
/// notifications, an observation pump into @State) failed to fire or failed to
/// render. Managing the status item ourselves and creating a *fresh*
/// NSHostingController per open makes a current render a construction
/// guarantee, and inside a plain popover SwiftUI observation behaves normally.
/// Don't migrate back to MenuBarExtra without re-verifying all of the above.
@main
struct ForemanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // LSUIElement app with an AppKit-managed status item: no SwiftUI
        // scenes to show. Settings is the conventional inert placeholder.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = ForemanSession()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var iconPump: ObservationPump?

    func applicationDidFinishLaunching(_: Notification) {
        session.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        popover.behavior = .transient
        updateIcon()
        // AppKit owns the icon, so keeping it current is a plain callback —
        // no SwiftUI invalidation involved.
        iconPump = ObservationPump(
            tracking: { [session] in _ = session.isAnyWorkerLive },
            onChange: { [weak self] in self?.updateIcon() },
        )
    }

    /// Stop-on-quit lifecycle: Foreman owns its worker processes, so quitting
    /// the app tears them all down rather than leaving orphans.
    func applicationWillTerminate(_: Notification) {
        session.stopAllWorkers()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        // A fresh hosting controller per open: the menu always renders the
        // session's current state (and onAppear genuinely runs per open, so
        // the rescan-on-open behavior needs no window-event detection).
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(session: session),
        )
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Filled hammer while any worker is live, so the menu bar shows at a
    /// glance that agents are available.
    private func updateIcon() {
        statusItem?.button?.image = NSImage(
            systemSymbolName: session.isAnyWorkerLive ? "hammer.fill" : "hammer",
            accessibilityDescription: "Foreman",
        )
    }
}
