import Observation

/// Re-registering observation of an `@Observable` graph: calls `onChange` on
/// the main actor after *every* change to the properties read by `tracking`,
/// not just the first, by re-registering after each notification.
///
/// This lets non-SwiftUI code react to `@Observable` state — the Foreman app
/// drives its AppKit status-item icon with one.
///
/// `onChange` runs on the next main-actor turn after a change, so any batch
/// of synchronous mutations is complete by the time it fires; read current
/// state from the model rather than trying to learn *what* changed. Changes
/// landing between a notification and the re-registration are coalesced into
/// that notification. The pump observes until `cancel()` or deallocation.
@MainActor
public final class ObservationPump {
    private let tracking: @MainActor () -> Void
    private let onChange: @MainActor () -> Void
    private var isCancelled = false

    /// Starts observing immediately. `tracking` should read every property
    /// the caller wants change notifications for; `onChange` is the reaction.
    public init(
        tracking: @escaping @MainActor () -> Void,
        onChange: @escaping @MainActor () -> Void,
    ) {
        self.tracking = tracking
        self.onChange = onChange
        register()
    }

    /// Stops future notifications. Idempotent.
    public func cancel() {
        isCancelled = true
    }

    private func register() {
        guard !isCancelled else { return }
        withObservationTracking {
            tracking()
        } onChange: { [weak self] in
            // willSet-time; defer to the next main-actor turn so the mutation
            // (and any synchronous batch it belongs to) has landed.
            Task { @MainActor [weak self] in
                guard let self, !isCancelled else { return }
                onChange()
                register()
            }
        }
    }
}
