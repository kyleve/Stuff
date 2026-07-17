import AppKit
import LedgerCore
import Observation
import SwiftUI

/// The status item and popover are AppKit (not `MenuBarExtra`) on purpose:
/// the menu-bar title mirrors observable model state on every change, and the
/// AppKit `NSStatusItem` + `Observations` loop drives that reliably (the same
/// reason the old Foreman app landed here). See the module README.
@main
struct LedgerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The only SwiftUI scene: the standard Settings window (Cmd-, / the
        // popover's Settings button). The menu-bar UI itself is AppKit-managed.
        Settings {
            SettingsView(session: appDelegate.session)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = LedgerSession()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var titleTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_: Notification) {
        session.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.image = NSImage(
            systemSymbolName: "dollarsign.circle",
            accessibilityDescription: "Cursor spend",
        )
        item.button?.imagePosition = .imageLeading
        statusItem = item

        updateTitle()
        // AppKit owns the title, so keeping it current is a plain loop: the
        // stdlib Observations sequence yields after every change to the
        // derived status title (no SwiftUI invalidation involved).
        titleTask = Task { [weak self, session] in
            for await _ in Observations({ @MainActor in session.statusTitle }) {
                self?.updateTitle()
            }
        }
    }

    /// Stop the refresh loop on quit.
    func applicationWillTerminate(_: Notification) {
        session.stop()
    }

    /// Status-item click: dismiss the popover when it's open, otherwise show
    /// it anchored to the button (and refresh spend as it opens).
    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        let popover = popover ?? makePopover()
        self.popover = popover

        if popover.isShown {
            popover.performClose(nil)
            return
        }
        session.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The popover's own window must become key for text fields / buttons to
        // take input reliably.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: SpendView(session: session),
        )
        return popover
    }

    /// Shows the current-cycle dollar amount beside the icon while spend is
    /// loaded, and nothing (icon only) otherwise.
    private func updateTitle() {
        let title = session.statusTitle
        statusItem?.button?.title = title == "—" ? "" : " \(title)"
    }
}
