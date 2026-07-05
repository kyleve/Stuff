import AppKit
import ForemanCore
import SwiftUI

/// Why AppKit (NSStatusItem + NSWindow) instead of MenuBarExtra:
/// MenuBarExtra(.window) builds its content hierarchy once at launch and loses
/// SwiftUI's observation of it — @Observable mutations landing while the panel
/// was closed never rendered, and every "detect the open and force a refresh"
/// hook we tried (onAppear, controlActiveState, key-window and occlusion
/// notifications, an observation pump into @State) failed to fire or failed to
/// render. Managing the status item ourselves sidesteps all of it: inside a
/// regular window, SwiftUI observation and key-window notifications behave
/// normally. Don't migrate back to MenuBarExtra without re-verifying the above.
@main
struct ForemanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // LSUIElement app with an AppKit-managed status item: no SwiftUI
        // scenes to show. Settings is the conventional inert placeholder —
        // with its commands removed, or the app menu (visible during the
        // regular-app phase; see showWindow) would offer a "Settings…" item
        // that opens this empty window instead of the real settings sheet.
        Settings {
            EmptyView()
        }
        .commandsRemoved()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let session = ForemanSession()

    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var iconPump: ObservationPump?

    func applicationDidFinishLaunching(_: Notification) {
        session.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
        statusItem = item

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

    /// Status-item click: hide the window when it's frontmost, otherwise
    /// show and focus it. Closing the window (red button) just hides it —
    /// the app lives in the menu bar until Quit.
    @objc private func toggleWindow() {
        if let window, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
            restoreAccessoryPolicy()
            return
        }
        showWindow()
    }

    private func showWindow() {
        let window = window ?? makeWindow()
        self.window = window
        // Cooperative activation won't reliably hand key focus to an
        // accessory app, so promote to a regular app while the window is
        // shown (the Dock icon appears alongside it) and revert when it
        // hides. This is the established pattern for status-item apps that
        // open real windows.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // A minimized window reads isVisible == false, so a status-item click
        // routes here — but makeKeyAndOrderFront alone won't pull it out of
        // the Dock tray.
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        // Activation can land a beat after the request; re-assert key once
        // it has (harmless when the first attempt already took). Skip if the
        // window was hidden again in the meantime — ordering front here would
        // resurrect a window the user just dismissed.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Drops the Dock icon again once the window is hidden. Deferred a beat:
    /// flipping the policy in the same runloop turn as the hide leaves the
    /// menu bar glitchy.
    private func restoreAccessoryPolicy() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, window?.isVisible != true else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Red close button / Cmd-W: the window hides (`isReleasedWhenClosed`
    /// is off), so just drop the Dock icon.
    func windowWillClose(_: Notification) {
        restoreAccessoryPolicy()
    }

    /// Dock-icon click while the window is hidden (possible in the brief
    /// regular-app phase, or if the user hid the window without closing it).
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showWindow()
        }
        return true
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: MainWindowView(session: session),
            ),
        )
        window.title = "Foreman"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // We hold the reference and reuse the window across opens.
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ForemanMain")
        window.delegate = self
        return window
    }

    /// Regular windows post key events reliably (unlike the MenuBarExtra
    /// panel; see the header comment), so this is the rescan-on-open hook.
    func windowDidBecomeKey(_: Notification) {
        session.rescan()
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
