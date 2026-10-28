import Foundation
import PeriscopeCore

/// Trims the persisted Periscope store to the app's retention policy at launch.
///
/// Retention is two independent bounds, because either alone leaves a hole: an
/// age window alone lets a heavy-logging device grow the store large *within*
/// the window (the built-in ambient sources emit continuously, and spans emit
/// two records apiece), while a count alone would keep a quiet device's
/// year-old events forever. Applying both means the store is bounded by
/// whichever binds first.
///
/// A value type with the clock and the policy injected, so the pruning rule can
/// be exercised against an in-memory store instead of only through a real
/// launch.
struct LogHistoryPruner {
    /// How much history to keep.
    struct Policy: Equatable {
        /// Events older than this are dropped however few there are.
        let window: TimeInterval
        /// Ceiling on the events kept once the window has been applied.
        let eventLimit: Int
    }

    /// What one pass removed, split by which bound removed it — a quiet device
    /// should only ever report `expired`, so a nonzero `overflowed` is the
    /// signal that this install out-logs its window.
    struct Outcome: Equatable {
        let expired: Int
        let overflowed: Int
    }

    let policy: Policy
    let now: @Sendable () -> Date

    /// Apply the window, then the cap; returns what each removed.
    ///
    /// Order matters: the window usually does all the work, and applying the cap
    /// *after* it means the cap counts what actually survived rather than rows
    /// that were about to expire anyway.
    func prune(_ store: PeriscopeStore) async throws -> Outcome {
        let cutoff = now().addingTimeInterval(-policy.window)
        let expired = try await store.pruneEvents(olderThan: cutoff)
        let overflowed = try await store.pruneEvents(keepingNewest: policy.eventLimit)
        return Outcome(expired: expired, overflowed: overflowed)
    }
}

extension LogHistoryPruner.Policy {
    /// What the Where app ships.
    ///
    /// 100 days is long enough to investigate a bug reported a season late. The
    /// 50k-event ceiling is the size half: at the low-hundreds-of-bytes a stored
    /// event costs (payload JSON plus its row), it bounds the database in the
    /// tens of megabytes — diagnostics shouldn't be the largest thing the app
    /// keeps on disk — while still holding far more than a normal week of
    /// ambient events and spans.
    static let standard = Self(
        window: 100 * 24 * 60 * 60,
        eventLimit: 50000,
    )
}
