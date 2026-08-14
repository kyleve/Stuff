import PeriscopeCore
import SwiftUI

extension EnvironmentValues {
    /// The accumulated context, or `nil` above the first `logContext`
    /// modifier. Internal so the public accessor can supply the fallback.
    @Entry var accumulatedLogContext: LogContext?

    /// The accumulated log context: every scope and tag contributed by
    /// enclosing ``SwiftUICore/View/logContext(_:)-(Log<_>)`` modifiers,
    /// nearest one primary. Views log freeform directly
    /// (`log.info("tapped")`) or derive typed loggers
    /// (`log(PhotoLogs.self)`).
    ///
    /// Outside any `logContext` modifier this falls back to a root context
    /// on `Periscope.shared`, mirroring `Log.current`.
    public var logContext: LogContext {
        accumulatedLogContext ?? LogContext()
    }
}

extension View {
    /// Contribute `log`'s context to this view hierarchy: descendants'
    /// `\.logContext` links these scopes and tags onto whatever enclosing
    /// modifiers already contributed (this log primary — the nearest
    /// modifier wins), so views log with the full model + UI context "for
    /// free".
    ///
    /// ```swift
    /// PhotoDetailView()
    ///     .logContext(model.photoLog)   // model-layer context
    ///     .logContext(screenLog)        // this screen's context
    /// ```
    public func logContext(_ log: Log<some LogScopeDefinition>) -> some View {
        logContext(log.context)
    }

    /// Contribute a type-erased context to this view hierarchy.
    public func logContext(_ context: LogContext) -> some View {
        transformEnvironment(\.accumulatedLogContext) { current in
            current = current.map { context.linked(with: $0) } ?? context
        }
    }

    /// Contribute a `LogContextProviding` model's instance context —
    /// `.logContext(model.photo)` scopes descendants' logging to that
    /// object.
    public func logContext(_ provider: some LogContextProviding) -> some View {
        logContext(provider.log)
    }
}
