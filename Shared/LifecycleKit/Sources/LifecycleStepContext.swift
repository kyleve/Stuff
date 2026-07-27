import Observation

/// The reporting channel the engine hands each running trunk step.
///
/// The engine creates one per step run and publishes it in
/// `LifecycleRunner.Phase.running`, so the host's splash can show what the
/// launch is doing; the step writes `progress`/`message` as it works. Both
/// are observable, so a rendered splash re-renders as the step reports.
@MainActor
@Observable
public final class LifecycleStepContext {
    /// The running step's identity, for splash copy and tests.
    public let stepID: AnyHashable

    /// Why the app is launching, in case the reporting surface wants to adapt.
    public let reason: LifecycleReason

    /// Determinate progress in `0...1` for the host to show, or nil for an
    /// indeterminate spinner.
    public var progress: Double?

    /// A short, user-presentable status line for the host to show.
    public var message: String?

    /// Create a standalone context. The engine creates one per step run, but
    /// this is public so consumers can drive reporting surfaces in previews
    /// and tests without an engine.
    public init(stepID: AnyHashable, reason: LifecycleReason) {
        self.stepID = stepID
        self.reason = reason
    }
}
