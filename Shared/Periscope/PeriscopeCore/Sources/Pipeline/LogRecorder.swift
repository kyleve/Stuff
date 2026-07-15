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

    /// Whether a record at `level` in `scopes` would be kept. `Log` checks
    /// this before rendering freeform messages so filtered-out logging
    /// skips string construction; recorders must still enforce their own
    /// policy inside `record`.
    func shouldRecord(level: LogLevel, scopes: [ScopeID]) -> Bool

    /// Track a span opened by `Log.begin(for:lifetime:relaunch:)`,
    /// recording `began` (the span's `SpanBegan`; `nil` when the begin-time
    /// floors hid the whole pair) *atomically* with the registration: a
    /// span must never be visible for closing before its began is in the
    /// pipeline, or a racing supersede or `end(for:)` could record the
    /// span's end first. When `key` was already open, the prior span is
    /// returned (removed) so the caller can close it as superseded — that
    /// end trails the new began, which is fine: the prior span's own began
    /// was recorded when *it* registered.
    func beginSpan(key: SpanKey, span: OpenSpan, began: LogRecord?) -> OpenSpan?

    /// Stop tracking and return the open span for `key`, if any.
    func closeSpan(key: SpanKey) -> OpenSpan?
}
