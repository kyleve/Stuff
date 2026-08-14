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

/// The built-in scope for timed operation events.
@LogScope("span")
public enum SpanLog {
    /// Marks the start of a timed span (`Log.measure` / `Log.begin(for:)`).
    /// Carries the span's lifetime and relaunch policy so the watchdog and the
    /// relaunch sweep can honor them from the persisted payload alone.
    @LogEvent("began")
    public struct Began {
        public enum LifetimeMode: String, CaseIterable, Codable, Sendable {
            case scoped
            case bounded
            case indefinite
        }

        /// Half of a span pair — see `LogEvent.isProtectedFromDropping`.
        public static let isProtectedFromDropping = true

        @LogField("span_id", exposure: .restricted, kind: .identifier)
        public var spanID: SpanID

        @LogField("name", exposure: .restricted, kind: .technicalState)
        public var name: String

        @LogField("lifetime", exposure: .restricted, kind: .technicalState)
        public var lifetimeMode: SpanLog.Began.LifetimeMode

        @LogField("budget_ms", exposure: .shareable, kind: .duration)
        public var budget: Duration?

        @LogField("relaunch_policy", exposure: .shareable, kind: .category)
        public var relaunchPolicy: SpanRelaunchPolicy

        public var lifetime: SpanLifetime {
            switch lifetimeMode {
                case .scoped: .scoped
                case .bounded: .bounded(budget: budget ?? .zero)
                case .indefinite: .indefinite
            }
        }

        public var message: String {
            "▶ \(name)"
        }
    }

    /// Marks the end of a timed span: the measured duration and how it ended.
    @LogEvent("ended")
    public struct Ended {
        /// Half of a span pair — see `LogEvent.isProtectedFromDropping`.
        public static let isProtectedFromDropping = true

        @LogField("span_id", exposure: .restricted, kind: .identifier)
        public var spanID: SpanID

        @LogField("name", exposure: .restricted, kind: .technicalState)
        public var name: String

        @LogField("duration_ms", exposure: .shareable, kind: .duration)
        public var duration: Duration?

        @LogField("exit", exposure: .shareable, kind: .category)
        public var exitMode: SpanExit.Mode

        @LogField("exit_reason", exposure: .restricted, kind: .errorDetails)
        public var exitReason: String?

        public var exit: SpanExit {
            SpanExit(mode: exitMode, reason: exitReason)
        }

        public var level: LogLevel {
            switch exitMode {
                case .success, .cancelled: .info
                case .failure, .superseded, .expired, .orphaned: .warning
            }
        }

        public var message: String {
            var text = "◀ \(name) \(exitMode.described)"
            if let exitReason {
                text += ": \(exitReason)"
            }
            if let duration {
                text += " (\(duration.formatted()))"
            }
            return text
        }

        /// Best-effort recovery of the span name from a rendered ``message``.
        public static func nameRecovered(
            fromMessage message: String,
            exit mode: SpanExit.Mode?,
        ) -> String {
            var text = message.hasPrefix("◀ ") ? String(message.dropFirst(2)) : message
            if let mode, let exitWord = text.range(of: " " + mode.described) {
                text = String(text[..<exitWord.lowerBound])
            } else if text.hasSuffix(")"),
                      let duration = text.range(of: " (", options: .backwards)
            {
                text = String(text[..<duration.lowerBound])
            }
            return text
        }
    }

    /// Emitted while a budgeted `measure` closure is still running past its budget.
    @LogEvent("overdue", level: .warning)
    public struct Overdue {
        @LogField("span_id", exposure: .restricted, kind: .identifier)
        public var spanID: SpanID

        @LogField("name", exposure: .restricted, kind: .technicalState)
        public var name: String

        @LogField("budget_ms", exposure: .shareable, kind: .duration)
        public var budget: Duration

        public var message: String {
            "⏰ \(name) still running past its \(budget.formatted()) budget"
        }
    }
}

public typealias SpanBegan = SpanLog.Began
public typealias SpanEnded = SpanLog.Ended
public typealias SpanOverdue = SpanLog.Overdue

extension SpanLifetime {
    fileprivate var classifiedMode: SpanBegan.LifetimeMode {
        switch self {
            case .scoped: .scoped
            case .bounded: .bounded
            case .indefinite: .indefinite
        }
    }

    fileprivate var classifiedBudget: Duration? {
        guard case let .bounded(budget) = self else { return nil }
        return budget
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

extension SpanOverdue: SpanCarrying {}

extension LogRecord {
    /// The pair-integrity fallback for a redaction hook that tries to
    /// suppress a protected span record: the same event with its PII
    /// carriers removed — tags and attachments dropped, a `SpanEnded`'s
    /// freeform exit reason blanked. Identity, date, scopes, and the
    /// floor bypass are preserved. (Span names are typed tokens by
    /// convention, not user data.)
    func strippedOfSensitivePayload() -> LogRecord {
        var strippedEvent: any LogEvent = event
        if let ended = event as? SpanEnded {
            strippedEvent = SpanEnded(
                spanID: .restricted(.identifier, ended.spanID),
                name: .restricted(.technicalState, ended.name),
                duration: .shared(.duration, ended.duration),
                exitMode: .shared(.category, ended.exitMode),
                exitReason: .restricted(.errorDetails, nil),
            )
        }
        var stripped = LogRecord(
            id: id,
            date: date,
            event: strippedEvent,
            scopes: scopes,
            tags: [],
            attachments: [],
            callSite: callSite,
        )
        stripped.bypassesFloors = bypassesFloors
        return stripped
    }

    /// The span this record belongs to, when its event is a span event.
    public var spanID: SpanID? {
        (event as? SpanCarrying)?.spanID
    }

    /// How the span ended, when this record is a ``SpanEnded`` — the store
    /// persists its mode as a queryable column.
    public var spanExit: SpanExit? {
        (event as? SpanEnded)?.exit
    }

    /// What a relaunch should do with this span, when this record is a
    /// ``SpanBegan`` — the store persists it as a column so the next launch's
    /// orphan sweep decides from an indexed value rather than by decoding
    /// every unmatched began's payload.
    public var spanRelaunchPolicy: SpanRelaunchPolicy? {
        (event as? SpanBegan)?.relaunchPolicy
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
    public let tags: [LogTag]

    public init(
        id: SpanID,
        name: String,
        start: ContinuousClock.Instant,
        lifetime: SpanLifetime,
        beganRecorded: Bool,
        scopes: [ScopeID],
        tags: [LogTag],
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
/// identifier. Span names resolve against `Scope.SpanName`, which defaults
/// to `String` — declare a `SpanName` enum on the event type for
/// compiler-checked tokens (`log.measure(.saveEvent)`), the recommended
/// style for structured events; freeform loggers measure ad hoc.
extension Log {
    /// Times `body` between paired ``SpanBegan``/``SpanEnded`` events
    /// sharing one ``SpanID``. The exit is derived automatically: return →
    /// `.success`, throw → `.failure` (with the error described),
    /// `CancellationError` → `.cancelled`. Names resolve against
    /// `Scope.SpanName`, so typed scopes get leading-dot tokens
    /// (`log.measure(.saveEvent) { … }`).
    @discardableResult
    public func measure<R>(_ name: Scope.SpanName, _ body: () throws -> R) rethrows -> R {
        try timedSpan(named: String(describing: name), budget: nil, body)
    }

    /// A `measure` with an expectation: if `body` is still running after
    /// `budget`, a ``SpanOverdue`` warning fires *while it hangs* — the
    /// span itself still ends normally with its derived exit.
    @discardableResult
    public func measure<R>(
        _ name: Scope.SpanName,
        budget: Duration,
        _ body: () throws -> R,
    ) rethrows -> R {
        try timedSpan(named: String(describing: name), budget: budget, body)
    }

    /// The `async` form of `measure`; preserves the caller's isolation.
    @discardableResult
    public func measure<R>(
        _ name: Scope.SpanName,
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
        _ name: Scope.SpanName,
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
                emit(SpanOverdue(
                    spanID: .restricted(.identifier, span),
                    name: .restricted(.technicalState, name),
                    budget: .shared(.duration, budget),
                ))
            }
        }
    }

    /// Signposts the start and, when the floors admit it, records the
    /// `SpanBegan`. Returns the floor decision the whole pair follows —
    /// including the overdue sentinel, which stays silent for a span the
    /// floors hid.
    private func beginMeasuredSpan(_ span: SpanID, name: String) -> Bool {
        let began = SpanBegan(
            spanID: .restricted(.identifier, span),
            name: .restricted(.technicalState, name),
            lifetimeMode: .restricted(.technicalState, .scoped),
            budget: .shared(.duration, nil),
            relaunchPolicy: .shared(.category, .endsWithProcess),
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
        let ended = SpanEnded(
            spanID: .restricted(.identifier, span),
            name: .restricted(.technicalState, name),
            duration: .shared(.duration, duration),
            exitMode: .shared(.category, exit.mode),
            exitReason: .restricted(.errorDetails, exit.reason),
        )
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
            spanID: .restricted(.identifier, SpanID()),
            name: .restricted(.technicalState, name),
            lifetimeMode: .restricted(.technicalState, lifetime.classifiedMode),
            budget: .shared(.duration, lifetime.classifiedBudget),
            relaunchPolicy: .shared(.category, relaunch),
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
        var beganRecord: LogRecord?
        if beganRecorded {
            var record = LogRecord(
                date: Date(),
                event: began,
                scopes: scopes.map(\.id),
                tags: tags,
            )
            record.bypassesFloors = true
            beganRecord = record
        }
        // Registration and the began land atomically (see
        // `LogRecorder.beginSpan`), so a racing supersede or `end(for:)`
        // can't record this span's end first. The superseded close follows
        // the *new* began — cause before effect: the re-begin is what
        // closed it.
        if let superseded = recorder.beginSpan(key: key, span: span, began: beganRecord) {
            SpanSignposts.end(superseded.id)
            if superseded.beganRecorded {
                var closing = LogRecord(
                    date: Date(),
                    event: SpanEnded(
                        spanID: .restricted(.identifier, superseded.id),
                        name: .restricted(.technicalState, superseded.name),
                        duration: .shared(.duration, span.start - superseded.start),
                        exitMode: .shared(.category, .superseded),
                        exitReason: .restricted(.errorDetails, nil),
                    ),
                    scopes: superseded.scopes,
                    tags: superseded.tags,
                )
                closing.bypassesFloors = true
                recorder.record(closing)
            }
        }
        SpanSignposts.begin(span.id, name: name)
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
                spanID: .restricted(.identifier, open.id),
                name: .restricted(.technicalState, open.name),
                duration: .shared(.duration, ContinuousClock().now - open.start),
                exitMode: .shared(.category, exit.mode),
                exitReason: .restricted(.errorDetails, exit.reason),
            ),
            bypassingFloors: true,
        )
    }
}
