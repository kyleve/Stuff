import Foundation
import os

/// The identity shared by a span's begin and end events.
public struct SpanID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init() {
        rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString
    }
}

extension SpanID: Codable {
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Marks the start of a timed span (`Log.measure` / `Log.begin(for:)`).
public struct SpanBegan: LogEvent {
    public static let eventName = "span-began"

    public let spanID: SpanID
    public let name: String

    public var message: String {
        "▶ \(name)"
    }

    public init(spanID: SpanID, name: String) {
        self.spanID = spanID
        self.name = name
    }
}

/// Marks the end of a timed span, carrying the measured duration
/// (monotonic — `ContinuousClock`, not wall-clock deltas).
public struct SpanEnded: LogEvent {
    public static let eventName = "span-ended"

    public let spanID: SpanID
    public let name: String
    public let duration: Duration

    public var message: String {
        "◀ \(name) (\(duration.formatted()))"
    }

    public init(spanID: SpanID, name: String, duration: Duration) {
        self.spanID = spanID
        self.name = name
        self.duration = duration
    }
}

/// Lets sinks and the store identify span events without matching each
/// concrete type.
protocol SpanCarrying {
    var spanID: SpanID { get }
}

extension SpanBegan: SpanCarrying {}
extension SpanEnded: SpanCarrying {}

extension LogRecord {
    /// The span this record belongs to, when its event is a span event.
    public var spanID: SpanID? {
        (event as? SpanCarrying)?.spanID
    }
}

/// Identifies an open `begin(for:)` span: begin and end pair when they use
/// the same identifier on a logger with the same primary scope — and since
/// scopes are deterministic, that logger can be rebuilt anywhere.
public struct SpanKey: Hashable, Sendable {
    public let scope: ScopeID
    public let identifier: String

    public init(scope: ScopeID, identifier: String) {
        self.scope = scope
        self.identifier = identifier
    }
}

/// A span begun with `Log.begin(for:)` that hasn't ended yet.
public struct OpenSpan: Sendable {
    public let id: SpanID
    public let name: String
    public let start: ContinuousClock.Instant

    public init(id: SpanID, name: String, start: ContinuousClock.Instant) {
        self.id = id
        self.name = name
        self.start = start
    }
}

/// Mirrors span begin/end pairs to os_signpost so Periscope spans appear in
/// Instruments' timeline. Signposts fire at emission time (not sink
/// delivery), so intervals carry real durations.
enum SpanSignposts {
    private static let signposter = OSSignposter(
        subsystem: "com.stuff.periscope",
        category: "Spans",
    )

    private static let intervals = OSAllocatedUnfairLock<[SpanID: OSSignpostIntervalState]>(
        uncheckedState: [:],
    )

    static func begin(_ span: SpanID, name: String) {
        let state = signposter.beginInterval(
            "Span",
            id: signposter.makeSignpostID(),
            "\(name, privacy: .public)",
        )
        intervals.withLockUnchecked { $0[span] = state }
    }

    static func end(_ span: SpanID) {
        let state = intervals.withLockUnchecked { $0.removeValue(forKey: span) }
        guard let state else { return }
        signposter.endInterval("Span", state)
    }
}

/// Timing: measure closures, and open-ended begin/end spans keyed by
/// identifier. Span names are typed tokens (`log.measure(.saveEvent)`), not
/// raw strings.
extension Log {
    /// Times `body` between paired ``SpanBegan``/``SpanEnded`` events
    /// sharing one ``SpanID``. The end event is emitted even when `body`
    /// throws. Names resolve against `Event.SpanName`, so typed events get
    /// leading-dot tokens (`log.measure(.saveEvent) { … }`).
    @discardableResult
    public func measure<R>(_ name: Event.SpanName, _ body: () throws -> R) rethrows -> R {
        let span = SpanID()
        let spanName = String(describing: name)
        let clock = ContinuousClock()
        let start = clock.now
        SpanSignposts.begin(span, name: spanName)
        emit(SpanBegan(spanID: span, name: spanName))
        defer {
            SpanSignposts.end(span)
            emit(SpanEnded(spanID: span, name: spanName, duration: clock.now - start))
        }
        return try body()
    }

    /// The `async` form of `measure`; preserves the caller's isolation.
    @discardableResult
    public func measure<R>(
        _ name: Event.SpanName,
        isolation _: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R,
    ) async rethrows -> R {
        let span = SpanID()
        let spanName = String(describing: name)
        let clock = ContinuousClock()
        let start = clock.now
        SpanSignposts.begin(span, name: spanName)
        emit(SpanBegan(spanID: span, name: spanName))
        defer {
            SpanSignposts.end(span)
            emit(SpanEnded(spanID: span, name: spanName, duration: clock.now - start))
        }
        return try await body()
    }

    /// Open a span for `id` — e.g. `log.begin(for: payment)` when a payment
    /// flow starts. Close it later with ``end(for:)`` from any logger with
    /// the same primary scope. Beginning an already-open span logs a
    /// warning instead of restarting it.
    public func begin(for id: some Hashable & Sendable) {
        let name = String(describing: id)
        let key = SpanKey(scope: primaryScope.id, identifier: name)
        guard let span = recorder.openSpan(key: key, name: name, start: ContinuousClock().now)
        else {
            warning("begin(for: \(name)) while that span is already open")
            return
        }
        SpanSignposts.begin(span, name: name)
        emit(SpanBegan(spanID: span, name: name))
    }

    /// Close the span opened with ``begin(for:)`` for the same identifier,
    /// emitting the ``SpanEnded`` with the measured duration. Ending a span
    /// that isn't open logs a warning.
    public func end(for id: some Hashable & Sendable) {
        let name = String(describing: id)
        let key = SpanKey(scope: primaryScope.id, identifier: name)
        guard let open = recorder.closeSpan(key: key) else {
            warning("end(for: \(name)) without a matching begin")
            return
        }
        SpanSignposts.end(open.id)
        emit(SpanEnded(
            spanID: open.id,
            name: open.name,
            duration: ContinuousClock().now - open.start,
        ))
    }
}
