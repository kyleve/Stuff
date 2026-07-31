import AppKit
import CoreFoundation
import SwiftUI
import WhereSurface

@MainActor
final class WhereMenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private let model: WhereMenuBarModel
    private var popover: NSPopover?
    private var statusItem: NSStatusItem?

    override init() {
        do {
            model = try WhereMenuBarModel(reader: WhereSurfaceStore.shared())
        } catch let error as WhereSurfaceStore.AppGroupUnavailableError {
            model = WhereMenuBarModel(appGroupUnavailable: error)
        } catch {
            assertionFailure("Unexpected WhereSurfaceStore error: \(error)")
            model = WhereMenuBarModel(
                appGroupUnavailable: WhereSurfaceStore.AppGroupUnavailableError(),
            )
        }
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        startObservingSurfaceChanges()
    }

    func applicationWillTerminate(_: Notification) {
        stopObservingSurfaceChanges()
    }

    fileprivate func surfaceDidChange() {
        model.refresh()
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: WhereMenuBarView(model: model),
        )
        self.popover = popover
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else {
            assertionFailure("NSStatusItem did not vend a button")
            self.statusItem = statusItem
            return
        }

        let accessibilityLabel = String(localized: .menuBarAccessibilityLabel)
        if let image = NSImage(
            systemSymbolName: "location.fill",
            accessibilityDescription: accessibilityLabel,
        ) {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            assertionFailure("The location.fill system symbol is unavailable")
            button.title = "●"
            button.imagePosition = .noImage
        }
        button.setAccessibilityLabel(accessibilityLabel)
        button.target = self
        button.action = #selector(togglePopover)
        self.statusItem = statusItem
    }

    @objc
    private func togglePopover() {
        guard
            let button = statusItem?.button,
            let popover
        else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }

    private func startObservingSurfaceChanges() {
        stopObservingSurfaceChanges()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            whereMenuBarSurfaceChanged,
            WhereSurfaceChangeNotification.name as CFString,
            nil,
            .deliverImmediately,
        )
    }

    private func stopObservingSurfaceChanges() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(
                rawValue: WhereSurfaceChangeNotification.name as CFString,
            ),
            nil,
        )
    }
}

private func whereMenuBarSurfaceChanged(
    _: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?,
) {
    guard let observer else { return }
    let delegate = Unmanaged<WhereMenuBarAppDelegate>
        .fromOpaque(observer)
        .takeUnretainedValue()
    Task { @MainActor in
        delegate.surfaceDidChange()
    }
}
