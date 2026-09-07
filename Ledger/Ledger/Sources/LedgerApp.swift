import AppKit
import LedgerCore
import SwiftUI

/// The status item and popover are AppKit (not `MenuBarExtra`) on purpose (the
/// same reason the old Foreman app landed here). The status item hosts a small
/// SwiftUI `MenuBarLabel` so the amount gets the numeric-text roll-over and
/// updates itself from the observable session. See the module README.
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

    func applicationDidFinishLaunching(_: Notification) {
        session.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.setAccessibilityTitle("Cursor spend")

        // Host the SwiftUI label inside the status button. It's click-through
        // (see ClickThroughHostingView) so the button still receives the click
        // that toggles the popover. A variable-length item doesn't auto-size to
        // a hosted view, so the label reports its width and we set the item's
        // length to match (otherwise the amount is clipped to just the icon).
        let label =
            ClickThroughHostingView(rootView: MenuBarLabel(session: session) { [weak self] width in
                self?.statusItem?.length = ceil(width)
            })
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            label.topAnchor.constraint(equalTo: button.topAnchor),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    /// Stop the refresh loop on quit.
    func applicationWillTerminate(_: Notification) {
        session.stop()
    }

    /// Status-item click: dismiss the popover when it's open, otherwise show it
    /// anchored to the button. Deliberately does not fetch — see below.
    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        let popover = popover ?? makePopover()
        self.popover = popover

        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Don't fetch on open — the periodic refresh loop keeps both the title
        // and the popover current; opening just shows the latest state. Use the
        // popover's Refresh button to force an immediate fetch.
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
}

/// An `NSHostingView` that never claims mouse hits, so the SwiftUI content it
/// draws is display-only and the enclosing status-item button keeps receiving
/// the click that toggles the popover.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not used")
    }
}
