import Foundation

/// The recording backend a `Log` emits into.
///
/// The production conformer is the `Periscope` system; tests use lightweight
/// in-memory recorders. Both methods are called synchronously from arbitrary
/// threads at log call sites, so implementations must not block.
public protocol LogRecorder: Sendable {
    /// Register a scope. Called on every `Log` derivation with a
    /// deterministic scope, so implementations must be idempotent per
    /// ``LogScope/id``.
    func defineScope(_ scope: LogScope)

    /// Record one emitted event.
    func record(_ record: LogRecord)
}
