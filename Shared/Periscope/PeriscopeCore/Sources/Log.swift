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
public struct Log<Event: LogEvent>: Sendable {
    /// The scopes events emitted here belong to: the primary scope first,
    /// then any linked scopes.
    public let scopes: [LogScope]

    /// The tags stamped on every event emitted here (see ``tagged(_:_:)``).
    public let tags: [LogTagKey: String]

    let recorder: any LogRecorder

    /// The scope this logger derives children from.
    public var primaryScope: LogScope {
        scopes[0]
    }

    /// A root logger whose scope is named after `Event`.
    public init(recorder: any LogRecorder) {
        self.init(scopes: [LogScope.root(named: Event.eventName)], tags: [:], recorder: recorder)
    }

    init(scopes: [LogScope], tags: [LogTagKey: String], recorder: any LogRecorder) {
        precondition(!scopes.isEmpty, "A Log must have at least one scope")
        self.scopes = scopes
        self.tags = tags
        self.recorder = recorder
        recorder.defineScope(scopes[0])
    }

    // MARK: Deriving children

    /// A child logger typed to `Child`, under a child scope named after it.
    public func callAsFunction<Child: LogEvent>(_: Child.Type) -> Log<Child> {
        deriving(childNamed: Child.eventName)
    }

    /// A child logger for a specific entity, under a child scope named by
    /// `id` — e.g. one scope per album, per payment, per request.
    public func callAsFunction(for id: some Hashable & Sendable) -> Log<Event> {
        deriving(childNamed: String(describing: id))
    }

    private func deriving<Child: LogEvent>(childNamed name: String) -> Log<Child> {
        var scopes = scopes
        scopes[0] = primaryScope.child(named: name)
        return Log<Child>(scopes: scopes, tags: tags, recorder: recorder)
    }

    // MARK: Linking

    /// A logger whose events reference both sides' scopes — the "join"
    /// between two contexts, e.g. a model object's log and the UI's log.
    /// Duplicate scopes collapse and tags merge; the left side stays
    /// primary and wins tag-key conflicts.
    public static func + (lhs: Log, rhs: Log<some LogEvent>) -> Log<Event> {
        lhs.linked(with: rhs)
    }

    /// The spelled-out form of `+`.
    public func linked(with other: Log<some LogEvent>) -> Log<Event> {
        var merged = scopes
        for scope in other.scopes where !merged.contains(scope) {
            merged.append(scope)
        }
        var tags = tags
        for (key, value) in other.tags where tags[key] == nil {
            tags[key] = value
        }
        return Log(scopes: merged, tags: tags, recorder: recorder)
    }

    // MARK: Tagging

    /// A logger that stamps `key: value` on every event it emits, on top of
    /// the tags already accumulated. Tags flow down derivations and links —
    /// tag a flow's root once (say, the current payment's ID) and every
    /// event under it carries the tag, wherever it sits in the tree.
    public func tagged(_ key: LogTagKey, _ value: String) -> Log<Event> {
        var tags = tags
        tags[key] = value
        return Log(scopes: scopes, tags: tags, recorder: recorder)
    }

    // MARK: Emitting

    /// Log a structured event with this logger's full context.
    public func callAsFunction(_ event: () -> Event) {
        emit(event())
    }

    /// Log a structured event with attached data — errors, payloads,
    /// screenshots (see ``LogAttachment``).
    public func callAsFunction(attachments: [LogAttachment], _ event: () -> Event) {
        emit(event(), attachments: attachments)
    }

    func emit(_ event: any LogEvent, attachments: [LogAttachment] = []) {
        recorder.record(LogRecord(
            date: Date(),
            event: event,
            scopes: scopes.map(\.id),
            tags: tags,
            attachments: attachments,
        ))
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
    ) {
        guard recorder.shouldRecord(level: level, scopes: scopes.map(\.id)) else { return }
        emit(Message(level: level, text()), attachments: attachments)
    }

    public func debug(_ text: @autoclosure () -> String, attachments: [LogAttachment] = []) {
        log(.debug, text(), attachments: attachments)
    }

    public func info(_ text: @autoclosure () -> String, attachments: [LogAttachment] = []) {
        log(.info, text(), attachments: attachments)
    }

    public func notice(_ text: @autoclosure () -> String, attachments: [LogAttachment] = []) {
        log(.notice, text(), attachments: attachments)
    }

    public func warning(_ text: @autoclosure () -> String, attachments: [LogAttachment] = []) {
        log(.warning, text(), attachments: attachments)
    }

    public func error(_ text: @autoclosure () -> String, attachments: [LogAttachment] = []) {
        log(.error, text(), attachments: attachments)
    }

    public func fault(_ text: @autoclosure () -> String, attachments: [LogAttachment] = []) {
        log(.fault, text(), attachments: attachments)
    }
}
