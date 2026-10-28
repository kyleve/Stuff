import Foundation

/// A destination in the `Periscope` pipeline — the OTel-exporter /
/// swift-log-`LogHandler` role.
///
/// Built-ins are ``OSLogSink`` (Console.app) and the SwiftData store; apps
/// register their own for remote upload, crash-reporter breadcrumbs, or test
/// assertions. Sinks receive work **asynchronously in batches** shortly
/// after emit — log call sites never wait on a sink.
///
/// The system guarantees a scope's definition is delivered before any record
/// referencing it, and preserves record order within and across batches.
public protocol LogSink: Sendable {
    /// Register scopes. May contain scopes delivered before (late-added
    /// sinks get the full registry replayed) — implementations must be
    /// idempotent per ``LogScope/id``.
    func defineScopes(_ scopes: [LogScope]) async

    /// Deliver a batch of records, oldest first.
    func write(_ records: [LogRecord]) async

    /// Persist anything buffered. Called at flush points — on demand, and
    /// (per the flush policy) when high-severity events demand durability.
    func flush() async
}
