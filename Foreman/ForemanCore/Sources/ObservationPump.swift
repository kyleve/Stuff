import Observation

/// Re-registering observation of an `@Observable` graph: calls `onChange` on
/// the main actor after *every* change to the properties read by `tracking`,
/// not just the first, by re-registering after each notification.
///
/// This exists because some SwiftUI hosts lose their own observation
/// dependencies — notably `MenuBarExtra(.window)` panel content, where a
/// mutation landing while the panel is closed is dropped and (tracking being
/// one-shot) the body never observes again. Views work around it by pairing
/// a pump with a `@State` counter: the pump bumps the counter, and the
/// `@State` change forces the body re-evaluation that SwiftUI's own tracking
/// failed to deliver.
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
