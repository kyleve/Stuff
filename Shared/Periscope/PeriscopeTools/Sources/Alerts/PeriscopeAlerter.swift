import Foundation
import PeriscopeCore

/// Receives high-severity records the moment they're emitted — the hook
/// behind the debug toast. Apps with their own toast/notification system
/// conform and pass their handler to ``PeriscopeAlerter``; the built-in
/// default is ``LocalNotificationAlertHandler``.
///
/// Handlers run on the main actor and must not log at or above the
/// alerter's threshold, or they'd alert themselves in a loop.
@MainActor
public protocol PeriscopeAlertHandler {
    func handle(_ record: LogRecord)
}

/// Watches a `Periscope` system's live records and routes everything at
/// `threshold` or above to a ``PeriscopeAlertHandler`` — the engine behind
/// "a toast appears when an error is logged". Intended for debug builds;
/// gate construction behind `#if DEBUG`:
///
/// ```swift
/// #if DEBUG
///     let alerter = PeriscopeAlerter(
///         system: .shared,
///         threshold: .warning,
///         handler: LocalNotificationAlertHandler(),
///     )
///     alerter.start()
/// #endif
/// ```
@MainActor
public final class PeriscopeAlerter {
    private let system: Periscope
    private let threshold: LogLevel
    private let handler: any PeriscopeAlertHandler
    private var task: Task<Void, Never>?

    public init(
        system: Periscope,
        threshold: LogLevel,
        handler: any PeriscopeAlertHandler,
    ) {
        self.system = system
        self.threshold = threshold
        self.handler = handler
    }

    deinit {
        task?.cancel()
    }

    /// Begin watching. Only records emitted after this point alert;
    /// starting twice is a no-op.
    public func start() {
        guard task == nil else { return }
        let stream = system.liveRecords()
        let threshold = threshold
        let handler = handler
        task = Task { @MainActor in
            for await record in stream {
                guard record.level >= threshold else { continue }
                handler.handle(record)
            }
        }
    }

    /// Stop watching; ``start()`` may be called again later.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
