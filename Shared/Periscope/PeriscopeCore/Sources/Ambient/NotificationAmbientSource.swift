import Foundation
import os

/// Base for ambient sources that observe `NotificationCenter`.
///
/// Registration is **target/selector** based (`addObserver(_:selector:…)`
/// with `self` as the observer), so teardown is a single
/// `removeObserver(self)` — there are no opaque tokens to retain, and
/// forgetting one can't immortalize the source the way a dropped
/// block-observer token would. `start` removes `self` before re-adding, so
/// a restart replaces the observation instead of doubling it.
///
/// Subclasses list the notifications they care about in ``observedNames``
/// and turn a delivered notification into an event in ``event(for:)`` (or,
/// for work that must hop threads, override ``receive(_:)``). A source that
/// wants to emit a snapshot at startup overrides ``started()``.
///
/// `@unchecked Sendable`: `NSObject` isn't `Sendable`, and the only mutable
/// state — the active logger — is guarded by a lock. Subclasses must keep
/// any state they add either immutable or synchronized.
open class NotificationAmbientSource: NSObject, AmbientEventSource, @unchecked Sendable {
    /// The logger handed in at `start`, read on the notification delivery
    /// thread; `nil` before `start`/after `stop`, which makes `emit` a no-op.
    private let activeLog = OSAllocatedUnfairLock<Log<AmbientEvent>?>(uncheckedState: nil)

    override public init() {
        super.init()
    }

    /// The notifications to observe. Override; the default observes nothing.
    open var observedNames: [Notification.Name] {
        []
    }

    public func start(log: Log<AmbientEvent>) {
        activeLog.withLockUnchecked { $0 = log }
        let center = NotificationCenter.default
        // Blanket-remove first so a restart re-adds rather than doubles.
        center.removeObserver(self)
        for name in observedNames {
            center.addObserver(self, selector: #selector(notify(_:)), name: name, object: nil)
        }
        started()
    }

    public func stop() {
        NotificationCenter.default.removeObserver(self)
        activeLog.withLockUnchecked { $0 = nil }
    }

    /// Called at the end of `start`; override to emit an initial snapshot.
    /// The default does nothing.
    open func started() {}

    /// The event to log for a delivered notification, or `nil` to skip it.
    /// Runs on the notification's delivery thread. Override.
    open func event(for _: Notification) -> AmbientEvent? {
        nil
    }

    /// Handle a delivered notification. The default logs ``event(for:)``;
    /// override when delivery must hop threads (e.g. reading main-actor
    /// state) before emitting.
    open func receive(_ notification: Notification) {
        guard let event = event(for: notification) else { return }
        emit(event)
    }

    /// Log `event` when started (a no-op after `stop`).
    public func emit(_ event: AmbientEvent) {
        guard let log = activeLog.withLockUnchecked({ $0 }) else { return }
        log { event }
    }

    @objc private func notify(_ notification: Notification) {
        receive(notification)
    }
}
