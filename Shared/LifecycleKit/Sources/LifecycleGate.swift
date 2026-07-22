/// A point where the launch function can park awaiting external (user)
/// resolution — first-run onboarding is the canonical example.
///
/// A gate carries no behavior of its own: conditionality is a plain `if`
/// around the `LifecycleContext.gate(_:value:)` call, and the work happens in
/// the UI. The type exists so the UI layer's registry can key a view on it
/// and statically recover `Value` — the trunk value the caller passes when
/// parking, handed to the registered view alongside the resolution handle.
/// The engine parks in `LifecycleRunner.Phase.awaitingGate` with a
/// `LifecycleGateHandle`; the registered view resolves it to resume — or fail
/// — the drive.
@MainActor
public protocol LifecycleGate {
    /// The value the caller passes when parking, delivered to the registered
    /// gate view (e.g. the session onboarding commits regions with).
    associatedtype Value: Sendable

    /// Stable identity used for run-once memoization and tests. Typed as
    /// `AnyHashable` so gates carry a real `Hashable` token (a typed enum
    /// case is preferred over a raw string); any `Hashable` converts
    /// implicitly.
    var id: AnyHashable { get }

    /// Which launch reasons this gate applies to. Defaults to `.foreground`:
    /// a gate's whole job is to wait for the user, which would park a
    /// headless launch forever, so it is skipped there — and, being
    /// unmemoized when skipped, parks when `enterForeground()` re-runs the
    /// launch function.
    var modes: LifecycleModeSet { get }
}

extension LifecycleGate {
    public var modes: LifecycleModeSet {
        .foreground
    }
}
