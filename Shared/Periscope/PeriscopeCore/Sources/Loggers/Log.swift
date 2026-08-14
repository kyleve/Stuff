import Foundation

/// A typed, hierarchical logger: a pure value that captures *where in the
/// system* events come from, and can only emit `Event` values (plus freeform
/// ``Message`` conveniences).
///
/// Loggers form a tree of scopes. Calling a log with an event type derives a
/// child logger typed to it; calling with an identifier derives a child scope
/// keyed to that identifier; `+` links two loggers so events carry both
/// contexts:
///
/// ```swift
/// let root = Log<AppLogs>(recorder: recorder)
/// let photos = root(PhotoLogs.self)          // child scope, typed PhotoLogs
/// let album = photos(for: album.id)          // child scope keyed by id
/// album { PhotoLogs.uploaded(photo.id) }     // emits with full context
///
/// let joined = album + uiLog                 // events reference both scopes
/// ```
///
/// Deriving the same path twice yields the same scope (see ``ScopeID``), so
/// loggers can be rebuilt anywhere without coordination.
@dynamicMemberLookup
public struct Log<Scope: LogScopeDefinition>: Sendable {
    /// The scopes events emitted here belong to: the primary scope first,
    /// then any linked scopes.
    public let scopes: [LogScope]

    /// The tags stamped on every event emitted here (see ``tagged(_:_:)``).
    public let tags: [LogTag]

    let recorder: any LogRecorder

    /// Resolves a macro-generated event method for this scope.
    public subscript<Method>(dynamicMember keyPath: KeyPath<Scope.LogMethods, Method>) -> Method {
        Scope.makeLogMethods(self)[keyPath: keyPath]
    }

    /// The scope this logger derives children from.
    public var primaryScope: LogScope {
        scopes[0]
    }

    /// A root logger whose scope uses the definition's stable name.
    public init(recorder: any LogRecorder) {
        self.init(scopes: [LogScope.root(named: Scope.scopeName)], tags: [], recorder: recorder)
    }

    init(scopes: [LogScope], tags: [LogTag], recorder: any LogRecorder) {
        precondition(!scopes.isEmpty, "A Log must have at least one scope")
        self.scopes = scopes
        self.tags = tags
        self.recorder = recorder
        recorder.defineScope(scopes[0])
    }

    // MARK: Deriving children

    /// A child logger typed to `Child`, under a child scope named after it.
    public func callAsFunction<Child: LogScopeDefinition>(_: Child.Type) -> Log<Child> {
        deriving(childNamed: Child.scopeName)
    }

    /// A child logger for a specific entity, under a child scope named by
    /// `id` — e.g. one scope per album, per payment, per request.
    public func callAsFunction(for id: some Hashable & Sendable) -> Log<Scope> {
        deriving(childNamed: String(describing: id))
    }

    private func deriving<Child: LogScopeDefinition>(childNamed name: String) -> Log<Child> {
        var scopes = scopes
        scopes[0] = primaryScope.child(named: name)
        return Log<Child>(scopes: scopes, tags: tags, recorder: recorder)
    }

    // MARK: Linking

    /// A logger whose events reference both sides' scopes — the "join"
    /// between two contexts, e.g. a model object's log and the UI's log.
    /// Duplicate scopes collapse and tags merge; the left side stays
    /// primary and wins tag-key conflicts.
    public static func + (lhs: Log, rhs: Log<some LogScopeDefinition>) -> Log<Scope> {
        lhs.linked(with: rhs)
    }

    /// The spelled-out form of `+`.
    public func linked(with other: Log<some LogScopeDefinition>) -> Log<Scope> {
        var merged = scopes
        for scope in other.scopes where !merged.contains(scope) {
            merged.append(scope)
        }
        return Log(scopes: merged, tags: tags.merging(other.tags), recorder: recorder)
    }

    // MARK: Retyping

    /// This same context — scopes, tags, recorder — retyped to emit a
    /// different event type. No child scope is derived (unlike calling with
    /// an event type); adapters use this to carry a context across a typed
    /// boundary, e.g. the SwiftUI environment's freeform accessor.
    public func retyped<Other: LogScopeDefinition>(to _: Other.Type) -> Log<Other> {
        Log<Other>(scopes: scopes, tags: tags, recorder: recorder)
    }

    // MARK: Tagging

    /// A logger that stamps `key: value` on every event it emits, on top of
    /// the tags already accumulated. Tags flow down derivations and links —
    /// tag a flow's root once (say, the current payment's ID) and every
    /// event under it carries the tag, wherever it sits in the tree.
    /// Values are typed (see ``LogTagValue``); `String`, `Int`, `Double`,
    /// and `Bool` convert directly. Re-tagging a key replaces its value.
    public func tagged(_ key: LogTagKey, _ value: some LogTagValueConvertible) -> Log<Scope> {
        var tags = tags
        tags.set(value.logTagValue, forKey: key)
        return Log(scopes: scopes, tags: tags, recorder: recorder)
    }

    // MARK: Emitting

    /// Records one event with this logger's scopes, tags, attachments, and call site.
    public func record(
        _ event: some LogEvent,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        emit(
            event,
            attachments: attachments,
            callSite: LogCallSite(function: function, fileID: fileID),
        )
    }

    func emit(
        _ event: any LogEvent,
        attachments: [LogAttachment] = [],
        bypassingFloors: Bool = false,
        callSite: LogCallSite? = nil,
    ) {
        var record = LogRecord(
            date: Date(),
            event: event,
            scopes: scopes.map(\.id),
            tags: tags,
            attachments: attachments,
            callSite: callSite,
        )
        record.bypassesFloors = bypassingFloors
        recorder.record(record)
    }
}

/// Freeform logging: every `Log` can emit ``Message`` events at any level,
/// regardless of its `Event` type — the generic constraint applies to custom
/// structured events only.
extension Log {
    public func log(
        _ level: LogLevel,
        _ text: @autoclosure () -> String,
        attachments: [LogAttachment] = [],
        function: StaticString = #function,
        fileID: StaticString = #fileID,
    ) {
        guard recorder.shouldRecord(level: level, scopes: scopes.map(\.id)) else { return }
        emit(
            Message(
                level: .restricted(.technicalState, level),
                text: .restricted(.arbitraryText, text()),
            ),
            attachments: attachments,
            callSite: LogCallSite(function: function, fileID: fileID),
        )
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
}
