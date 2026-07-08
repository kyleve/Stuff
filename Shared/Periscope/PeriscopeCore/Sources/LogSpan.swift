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
/// Carries the span's lifetime and relaunch policy so the watchdog and the
/// relaunch sweep can honor them from the persisted payload alone.
public struct SpanBegan: LogEvent {
    public static let eventName = "span-began"
    public static let eventVersion = 2

    public let spanID: SpanID
    public let name: String
    public let lifetime: SpanLifetime
    public let relaunchPolicy: SpanRelaunchPolicy

    public var message: String {
        "▶ \(name)"
    }

    public init(
        spanID: SpanID,
        name: String,
        lifetime: SpanLifetime,
        relaunchPolicy: SpanRelaunchPolicy,
    ) {
        self.spanID = spanID
        self.name = name
        self.lifetime = lifetime
        self.relaunchPolicy = relaunchPolicy
    }
}

/// Marks the end of a timed span: the measured duration (monotonic —
/// `ContinuousClock`; `nil` when unknowable, i.e. orphaned across process
/// death) and how it ended.
///
/// Abnormal exits (`superseded`, `expired`, `orphaned`, `failure`) log at
/// `.warning`; `success` and `cancelled` (a normal lifecycle outcome) stay
/// at `.info`.
public struct SpanEnded: LogEvent {
    public static let eventName = "span-ended"
    public static let eventVersion = 2

    public let spanID: SpanID
    public let name: String
    public let duration: Duration?
    public let exit: SpanExit

    public var level: LogLevel {
        switch exit.mode {
            case .success, .cancelled: .info
            case .failure, .superseded, .expired, .orphaned: .warning
        }
    }

    public var message: String {
        var text = "◀ \(name) \(exit.mode.described)"
        if let reason = exit.reason {
            text += ": \(reason)"
        }
        if let duration {
            text += " (\(duration.formatted()))"
        }
        return text
    }

    public init(spanID: SpanID, name: String, duration: Duration?, exit: SpanExit) {
        self.spanID = spanID
        self.name = name
        self.duration = duration
        self.exit = exit
    }
}

extension SpanExit.Mode {
    fileprivate var described: String {
        switch self {
            case .success: "succeeded"
            case .failure: "failed"
            case .cancelled: "cancelled"
            case .superseded: "superseded"
            case .expired: "expired"
            case .orphaned: "orphaned"
        }
    }
}

/// Lets sinks and the store identify span events without matching each
/// concrete type.
protocol SpanCarrying {
    var spanID: SpanID { get }
}

extension SpanBegan: SpanCarrying {}
extension SpanEnded: SpanCarrying {}

/// Emitted while a budgeted `measure` closure is still running past its
/// budget — the mid-hang signal. Unlike a bounded span's `.expired` close,
/// the span stays open and ends normally when (if) the closure returns.
public struct SpanOverdue: LogEvent {
    public static let eventName = "span-overdue"

    public let spanID: SpanID
    public let name: String
    public let budget: Duration

    public var level: LogLevel {
        .warning
    }

    public var message: String {
        "⏰ \(name) still running past its \(budget.formatted()) budget"
    }

    public init(spanID: SpanID, name: String, budget: Duration) {
        self.spanID = spanID
        self.name = name
        self.budget = budget
    }
}

extension SpanOverdue: SpanCarrying {}

extension LogRecord {
    /// The span this record belongs to, when its event is a span event.
    public var spanID: SpanID? {
        (event as? SpanCarrying)?.spanID
    }

    /// How the span ended, when this record is a ``SpanEnded`` — the store
    /// persists its mode as a queryable column.
    public var spanExit: SpanExit? {
        (event as? SpanEnded)?.exit
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

/// A span begun with `Log.begin(for:)` that hasn't ended yet. Carries the
/// beginning context (scopes, tags) so system-initiated closes — expiry,
/// supersession — attribute their `SpanEnded` like the begin was, plus the
/// begin-time floor decision the whole pair follows.
public struct OpenSpan: Sendable {
    public let id: SpanID
    public let name: String
    public let start: ContinuousClock.Instant
    public let lifetime: SpanLifetime
    /// Whether the floors admitted the `SpanBegan` when the span opened —
    /// its end (normal, expired, or superseded) is recorded iff this is
    /// true, so pairs never dangle across floor changes.
    public let beganRecorded: Bool
    public let scopes: [ScopeID]
    public let tags: [LogTagKey: String]

    public init(
        id: SpanID,
        name: String,
        start: ContinuousClock.Instant,
        lifetime: SpanLifetime,
        beganRecorded: Bool,
        scopes: [ScopeID],
        tags: [LogTagKey: String],
    ) {
        self.id = id
        self.name = name
        self.start = start
        self.lifetime = lifetime
        self.beganRecorded = beganRecorded
        self.scopes = scopes
        self.tags = tags
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
    /// sharing one ``SpanID``. The exit is derived automatically: return →
    /// `.success`, throw → `.failure` (with the error described),
    /// `CancellationError` → `.cancelled`. Names resolve against
    /// `Event.SpanName`, so typed events get leading-dot tokens
    /// (`log.measure(.saveEvent) { … }`).
    @discardableResult
    public func measure<R>(_ name: Event.SpanName, _ body: () throws -> R) rethrows -> R {
        try timedSpan(named: String(describing: name), budget: nil, body)
    }

    /// A `measure` with an expectation: if `body` is still running after
    /// `budget`, a ``SpanOverdue`` warning fires *while it hangs* — the
    /// span itself still ends normally with its derived exit.
    @discardableResult
    public func measure<R>(
        _ name: Event.SpanName,
        budget: Duration,
        _ body: () throws -> R,
    ) rethrows -> R {
        try timedSpan(named: String(describing: name), budget: budget, body)
    }

    /// The `async` form of `measure`; preserves the caller's isolation.
    @discardableResult
    public func measure<R>(
        _ name: Event.SpanName,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R,
    ) async rethrows -> R {
        try await timedSpan(
            named: String(describing: name),
            budget: nil,
            isolation: isolation,
            body,
        )
    }

    /// The `async` form of the budgeted `measure`.
    @discardableResult
    public func measure<R>(
        _ name: Event.SpanName,
        budget: Duration,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R,
    ) async rethrows -> R {
        try await timedSpan(
            named: String(describing: name),
            budget: budget,
            isolation: isolation,
            body,
        )
    }

    private func timedSpan<R>(
        named spanName: String,
        budget: Duration?,
        _ body: () throws -> R,
    ) rethrows -> R {
        let span = SpanID()
        let clock = ContinuousClock()
        let start = clock.now
        let recorded = beginMeasuredSpan(span, name: spanName)
        var sentinel: Task<Void, Never>?
        var overdueGate: OSAllocatedUnfairLock<Bool>?
        if recorded, let budget {
            let gate = OSAllocatedUnfairLock(initialState: false)
            overdueGate = gate
            sentinel = startOverdueSentinel(span: span, name: spanName, budget: budget, gate: gate)
        }
        defer { sentinel?.cancel() }
        do {
            let result = try body()
            endMeasuredSpan(
                span,
                name: spanName,
                duration: clock.now - start,
                exit: .success,
                recorded: recorded,
                overdueGate: overdueGate,
            )
            return result
        } catch {
            endMeasuredSpan(
                span,
                name: spanName,
                duration: clock.now - start,
                exit: Self.exit(for: error),
                recorded: recorded,
                overdueGate: overdueGate,
            )
            throw error
        }
    }

    private func timedSpan<R>(
        named spanName: String,
        budget: Duration?,
        isolation _: isolated (any Actor)?,
        _ body: () async throws -> R,
    ) async rethrows -> R {
        let span = SpanID()
        let clock = ContinuousClock()
        let start = clock.now
        let recorded = beginMeasuredSpan(span, name: spanName)
        var sentinel: Task<Void, Never>?
        var overdueGate: OSAllocatedUnfairLock<Bool>?
        if recorded, let budget {
            let gate = OSAllocatedUnfairLock(initialState: false)
            overdueGate = gate
            sentinel = startOverdueSentinel(span: span, name: spanName, budget: budget, gate: gate)
        }
        defer { sentinel?.cancel() }
        do {
            let result = try await body()
            endMeasuredSpan(
                span,
                name: spanName,
                duration: clock.now - start,
                exit: .success,
                recorded: recorded,
                overdueGate: overdueGate,
            )
            return result
        } catch {
            endMeasuredSpan(
                span,
                name: spanName,
                duration: clock.now - start,
                exit: Self.exit(for: error),
                recorded: recorded,
                overdueGate: overdueGate,
            )
            throw error
        }
    }

    /// One short-lived task per *budgeted* measure: sleep the budget and,
    /// if the closure hasn't finished (which cancels the sentinel), emit
    /// the overdue warning. The emission is serialized with the span's end
    /// through `gate`, so a sentinel that loses the race at the budget
    /// boundary can never record an overdue *after* the span ended.
    private func startOverdueSentinel(
        span: SpanID,
        name: String,
        budget: Duration,
        gate: OSAllocatedUnfairLock<Bool>,
    ) -> Task<Void, Never> {
        Task { [self] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled else { return }
            gate.withLock { ended in
                guard !ended else { return }
                emit(SpanOverdue(spanID: span, name: name, budget: budget))
            }
        }
    }

    /// Signposts the start and, when the floors admit it, records the
    /// `SpanBegan`. Returns the floor decision the whole pair follows —
    /// including the overdue sentinel, which stays silent for a span the
    /// floors hid.
    private func beginMeasuredSpan(_ span: SpanID, name: String) -> Bool {
        let began = SpanBegan(
            spanID: span,
            name: name,
            lifetime: .scoped,
            relaunchPolicy: .endsWithProcess,
        )
        let recorded = recorder.shouldRecord(level: began.level, scopes: scopes.map(\.id))
        SpanSignposts.begin(span, name: name)
        if recorded {
            emit(began, bypassingFloors: true)
        }
        return recorded
    }

    private func endMeasuredSpan(
        _ span: SpanID,
        name: String,
        duration: Duration,
        exit: SpanExit,
        recorded: Bool,
        overdueGate: OSAllocatedUnfairLock<Bool>?,
    ) {
        SpanSignposts.end(span)
        guard recorded else { return }
        let ended = SpanEnded(spanID: span, name: name, duration: duration, exit: exit)
        if let overdueGate {
            // MARK: - and-emit under the gate: after this, the sentinel stays

            // silent — never an overdue following the end.
            overdueGate.withLock { hasEnded in
                hasEnded = true
                emit(ended, bypassingFloors: true)
            }
        } else {
            emit(ended, bypassingFloors: true)
        }
    }

    private static func exit(for error: any Error) -> SpanExit {
        error is CancellationError ? .cancelled : .failure(String(describing: error))
    }

    /// Open a span for `id` — e.g. `log.begin(for: payment)` when a payment
    /// flow starts. Close it later with ``end(for:exit:)`` from any logger
    /// with the same primary scope. Beginning an already-open key closes
    /// the prior span as `.superseded` (the flow restarted) rather than
    /// refusing — no lockout, no leak.
    ///
    /// `lifetime` is deliberately explicit: bounded spans expire (and stop
    /// leaking) when they outlive their budget; indefinite spans are a
    /// conscious opt-in. `relaunch` decides what a later launch does with a
    /// span this process never ends.
    public func begin(
        for id: some Hashable & Sendable,
        lifetime: SpanLifetime,
        relaunch: SpanRelaunchPolicy = .endsWithProcess,
    ) {
        let name = String(describing: id)
        let key = SpanKey(scope: primaryScope.id, identifier: name)
        let began = SpanBegan(
            spanID: SpanID(),
            name: name,
            lifetime: lifetime,
            relaunchPolicy: relaunch,
        )
        // The floor decision is made once, here, for the whole pair: a
        // recorded began always gets its end (even if floors rise
        // mid-span), and a floored began silences the entire span —
        // never a dangling half. Signposts are unaffected; they're a
        // separate channel.
        let beganRecorded = recorder.shouldRecord(level: began.level, scopes: scopes.map(\.id))
        let span = OpenSpan(
            id: began.spanID,
            name: name,
            start: ContinuousClock().now,
            lifetime: lifetime,
            beganRecorded: beganRecorded,
            scopes: scopes.map(\.id),
            tags: tags,
        )
        if let superseded = recorder.openSpan(key: key, span: span) {
            SpanSignposts.end(superseded.id)
            if superseded.beganRecorded {
                var closing = LogRecord(
                    date: Date(),
                    event: SpanEnded(
                        spanID: superseded.id,
                        name: superseded.name,
                        duration: span.start - superseded.start,
                        exit: .superseded,
                    ),
                    scopes: superseded.scopes,
                    tags: superseded.tags,
                )
                closing.bypassesFloors = true
                recorder.record(closing)
            }
        }
        SpanSignposts.begin(span.id, name: name)
        if beganRecorded {
            emit(began, bypassingFloors: true)
        }
    }

    /// Close the span opened with ``begin(for:lifetime:relaunch:)`` for the
    /// same identifier, recording how it ended (`.success`,
    /// `.failure("card declined")`, `.cancelled`, …). Ending a span that
    /// isn't open logs a warning.
    public func end(for id: some Hashable & Sendable, exit: SpanExit) {
        let name = String(describing: id)
        let key = SpanKey(scope: primaryScope.id, identifier: name)
        guard let open = recorder.closeSpan(key: key) else {
            warning("end(for: \(name)) without a matching begin")
            return
        }
        SpanSignposts.end(open.id)
        guard open.beganRecorded else { return }
        emit(
            SpanEnded(
                spanID: open.id,
                name: open.name,
                duration: ContinuousClock().now - open.start,
                exit: exit,
            ),
            bypassingFloors: true,
        )
    }
}
