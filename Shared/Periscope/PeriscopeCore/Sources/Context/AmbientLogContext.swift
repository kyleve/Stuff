import Foundation

/// The task-local log context — the MDC / swift-distributed-tracing
/// pattern. `Log.withContext { … }` binds a context here; it propagates to
/// every structured child task, so deep helpers can log with full context
/// via `Log.current` without a logger threaded through each signature.
enum AmbientLogContext {
    struct Context {
        var scopes: [LogScope]
        var tags: [LogTag]
        var recorder: any LogRecorder
    }

    @TaskLocal static var current: Context?
}

extension Log {
    /// The ambient logger, typed to `Event`: the context bound by the
    /// nearest enclosing ``withContext(isolation:_:)``, or a root logger on
    /// ``Periscope/shared`` when none is bound. Freeform helpers use
    /// `Log<Message>.current`.
    public static var current: Log<Event> {
        guard let context = AmbientLogContext.current else {
            return Log()
        }
        return Log(scopes: context.scopes, tags: context.tags, recorder: context.recorder)
    }

    /// Runs `body` with this log's context ambient for the whole async call
    /// tree — `Log.current` inside (and in structured child tasks) carries
    /// these scopes. Nested calls link: the inner log's scopes come first,
    /// the enclosing ambient scopes follow.
    public func withContext<R>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R,
    ) async rethrows -> R {
        try await AmbientLogContext.$current.withValue(
            ambientContext(),
            operation: body,
            isolation: isolation,
        )
    }

    /// The synchronous form of ``withContext(isolation:_:)``.
    public func withContext<R>(_ body: () throws -> R) rethrows -> R {
        try AmbientLogContext.$current.withValue(ambientContext(), operation: body)
    }

    /// This log's scopes and tags, linked onto any already-ambient context
    /// (this log's scopes stay primary and its tags win key conflicts;
    /// duplicate scopes collapse).
    private func ambientContext() -> AmbientLogContext.Context {
        var scopes = scopes
        var tags = tags
        if let existing = AmbientLogContext.current {
            for scope in existing.scopes where !scopes.contains(scope) {
                scopes.append(scope)
            }
            tags = tags.merging(existing.tags)
        }
        return AmbientLogContext.Context(scopes: scopes, tags: tags, recorder: recorder)
    }
}
