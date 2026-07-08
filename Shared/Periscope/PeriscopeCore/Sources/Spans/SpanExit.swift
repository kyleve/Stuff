import Foundation

/// How a span ended: a closed set of modes plus an optional freeform
/// reason ("card declined", "user tapped cancel"). Richer payloads ride
/// along as `LogAttachment`s on the surrounding events.
public struct SpanExit: Hashable, Codable, Sendable {
    public enum Mode: String, CaseIterable, Codable, Sendable {
        /// The operation completed as intended.
        case success
        /// The operation failed. `measure` derives this from a thrown error.
        case failure
        /// The operation was called off — a normal lifecycle outcome, not a
        /// failure. `measure` derives this from `CancellationError`.
        case cancelled
        /// A new `begin(for:)` for the same key replaced this span — the
        /// flow restarted without ending.
        case superseded
        /// The watchdog closed a bounded span that outlived its budget.
        case expired
        /// A relaunch closed a span the previous process left open.
        case orphaned
    }

    public var mode: Mode
    public var reason: String?

    public init(mode: Mode, reason: String?) {
        self.mode = mode
        self.reason = reason
    }

    public static let success = SpanExit(mode: .success, reason: nil)
    public static let failure = SpanExit(mode: .failure, reason: nil)
    public static let cancelled = SpanExit(mode: .cancelled, reason: nil)
    public static let superseded = SpanExit(mode: .superseded, reason: nil)
    public static let orphaned = SpanExit(mode: .orphaned, reason: nil)

    public static func success(_ reason: String) -> SpanExit {
        SpanExit(mode: .success, reason: reason)
    }

    public static func failure(_ reason: String) -> SpanExit {
        SpanExit(mode: .failure, reason: reason)
    }

    public static func cancelled(_ reason: String) -> SpanExit {
        SpanExit(mode: .cancelled, reason: reason)
    }

    public static func expired(budget: Duration) -> SpanExit {
        SpanExit(mode: .expired, reason: "exceeded \(budget.formatted()) budget")
    }
}

/// How long a span is allowed to stay open.
public enum SpanLifetime: Hashable, Codable, Sendable {
    /// Bound to a `measure` closure — it cannot outlive the call.
    case scoped
    /// Expected to end within `budget`; the system's watchdog closes it as
    /// `.expired` past that, so a lost `end(for:)` can't leak it forever.
    case bounded(budget: Duration)
    /// Legitimately open-ended (a whole payment flow, a long download).
    /// Never expires while the process lives; on relaunch its
    /// ``SpanRelaunchPolicy`` decides.
    case indefinite
}

/// What a relaunch does with a span the previous process left open. The
/// policy is recorded on the `SpanBegan` payload, so the relaunch sweep can
/// honor it without any in-memory state surviving.
public enum SpanRelaunchPolicy: String, Codable, Sendable {
    /// The next launch closes it as `.orphaned` — the flow did not survive.
    case endsWithProcess
    /// The next launch leaves it open. (Resuming — re-seeding the open-span
    /// registry with wall-clock durations — is staged work; see
    /// `Shared/Periscope/TODOs.md`.)
    case survivesRelaunch
}
