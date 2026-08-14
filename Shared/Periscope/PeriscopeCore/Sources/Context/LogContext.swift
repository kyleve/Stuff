import Foundation

/// A type-erased logging context that retains scopes, tags, and its recorder.
public struct LogContext: Sendable {
    let scopes: [LogScope]
    let tags: [LogTag]
    let recorder: any LogRecorder

    public init(system: Periscope = .shared) {
        let log = Log<FreeformLogScope>(system: system)
        scopes = log.scopes
        tags = log.tags
        recorder = log.recorder
    }

    init(scopes: [LogScope], tags: [LogTag], recorder: any LogRecorder) {
        precondition(!scopes.isEmpty, "A LogContext must have at least one scope")
        self.scopes = scopes
        self.tags = tags
        self.recorder = recorder
    }

    /// Derives a typed child scope from this context.
    public func callAsFunction<Scope: LogScopeDefinition>(_: Scope.Type) -> Log<Scope> {
        Log<FreeformLogScope>(scopes: scopes, tags: tags, recorder: recorder)(Scope.self)
    }

    /// Derives a legacy event scope and records one event in a single expression.
    public func callAsFunction<Event: LogEvent>(
        _ type: Event.Type,
        function: StaticString = #function,
        fileID: StaticString = #fileID,
        _ event: () -> Event,
    ) {
        let child = callAsFunction(type)
        child.record(event(), function: function, fileID: fileID)
    }

    /// Links another context after this context while preserving this primary scope.
    public func linked(with other: LogContext) -> LogContext {
        var merged = scopes
        for scope in other.scopes where !merged.contains(scope) {
            merged.append(scope)
        }
        return LogContext(scopes: merged, tags: tags.merging(other.tags), recorder: recorder)
    }

    public func log(
        _ level: LogLevel,
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        erasedLog.log(level, text(), attachments: attachments, function: function, fileID: fileID)
    }

    public func debug(
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        log(.debug, text(), attachments: attachments, function: function, fileID: fileID)
    }

    public func info(
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        log(.info, text(), attachments: attachments, function: function, fileID: fileID)
    }

    public func notice(
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        log(.notice, text(), attachments: attachments, function: function, fileID: fileID)
    }

    public func warning(
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        log(.warning, text(), attachments: attachments, function: function, fileID: fileID)
    }

    public func error(
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        log(.error, text(), attachments: attachments, function: function, fileID: fileID)
    }

    public func fault(
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        log(.fault, text(), attachments: attachments, function: function, fileID: fileID)
    }

    private var erasedLog: Log<FreeformLogScope> {
        Log(scopes: scopes, tags: tags, recorder: recorder)
    }
}

extension Log {
    /// Returns this logger's context without deriving another scope.
    public var context: LogContext {
        LogContext(scopes: scopes, tags: tags, recorder: recorder)
    }
}
