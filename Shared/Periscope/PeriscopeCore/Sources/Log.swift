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

    let recorder: any LogRecorder

    /// The scope this logger derives children from.
    public var primaryScope: LogScope {
        scopes[0]
    }

    /// A root logger whose scope is named after `Event`.
    public init(recorder: any LogRecorder) {
        self.init(scopes: [LogScope.root(named: Event.eventName)], recorder: recorder)
    }

    init(scopes: [LogScope], recorder: any LogRecorder) {
        precondition(!scopes.isEmpty, "A Log must have at least one scope")
        self.scopes = scopes
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
        return Log<Child>(scopes: scopes, recorder: recorder)
    }

    // MARK: Linking

    /// A logger whose events reference both sides' scopes — the "join"
    /// between two contexts, e.g. a model object's log and the UI's log.
    /// Duplicate scopes collapse; the left side stays primary.
    public static func + (lhs: Log, rhs: Log<some LogEvent>) -> Log<Event> {
        lhs.linked(with: rhs)
    }

    /// The spelled-out form of `+`.
    public func linked(with other: Log<some LogEvent>) -> Log<Event> {
        var merged = scopes
        for scope in other.scopes where !merged.contains(scope) {
            merged.append(scope)
        }
        return Log(scopes: merged, recorder: recorder)
    }

    // MARK: Emitting

    /// Log a structured event with this logger's full context.
    public func callAsFunction(_ event: () -> Event) {
        emit(event())
    }

    func emit(_ event: any LogEvent) {
        recorder.record(LogRecord(date: Date(), event: event, scopes: scopes.map(\.id)))
    }
}

/// Freeform logging: every `Log` can emit ``Message`` events at any level,
/// regardless of its `Event` type — the generic constraint applies to custom
/// structured events only.
extension Log {
    public func log(_ level: LogLevel, _ text: @autoclosure () -> String) {
        emit(Message(level: level, text()))
    }

    public func debug(_ text: @autoclosure () -> String) {
        log(.debug, text())
    }

    public func info(_ text: @autoclosure () -> String) {
        log(.info, text())
    }

    public func notice(_ text: @autoclosure () -> String) {
        log(.notice, text())
    }

    public func warning(_ text: @autoclosure () -> String) {
        log(.warning, text())
    }

    public func error(_ text: @autoclosure () -> String) {
        log(.error, text())
    }

    public func fault(_ text: @autoclosure () -> String) {
        log(.fault, text())
    }
}
