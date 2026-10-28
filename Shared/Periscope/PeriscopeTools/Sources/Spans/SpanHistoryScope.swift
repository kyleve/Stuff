import Foundation
import PeriscopeCore

/// Which sessions a span-history reading draws its durations from.
///
/// Percentiles pooled across builds mislead in a specific way: a p99 taken half
/// from an unoptimized developer build and half from an optimized one describes
/// neither, and the reader can't tell from the number that it happened. Scoping
/// the reading is what makes a duration answerable — which is why the default is
/// deliberately ``all`` rather than the narrowest option: a reader who hasn't
/// chosen sees every recorded run, and narrowing is an explicit act.
enum SpanHistoryScope: Hashable, CaseIterable {
    /// Every recorded session, whatever it was built from.
    case all
    /// Only the session running now.
    case currentSession
    /// Every session built at the same `SWIFT_OPTIMIZATION_LEVEL` as the current
    /// one — the comparison that lets a reading span launches without mixing an
    /// optimized build's timings into an unoptimized one's.
    case sameOptimizationLevel

    var displayName: String {
        switch self {
            case .all: "All Builds"
            case .currentSession: "This Session"
            case .sameOptimizationLevel: "Same Optimization"
        }
    }

    /// The sessions in `sessions` this scope admits relative to `current`, or
    /// `nil` for "every session" — the caller then skips filtering entirely.
    ///
    /// Returns an empty set for a scope that needs a current session (or an
    /// optimization level) the store can't supply. ``resolvable(current:)``
    /// keeps such a scope out of the picker, so this is the unreachable branch;
    /// admitting *nothing* is the safe reading of it, since widening back to
    /// every build would silently answer a question the user didn't ask.
    func sessionIDs(in sessions: [LogSession], current: LogSession?) -> Set<UUID>? {
        switch self {
            case .all:
                return nil
            case .currentSession:
                guard let current else { return [] }
                return [current.id]
            case .sameOptimizationLevel:
                guard let level = current?.attributes[.optimizationLevel] else { return [] }
                return Set(
                    sessions
                        .filter { $0.attributes[.optimizationLevel] == level }
                        .map(\.id),
                )
        }
    }

    /// Whether this scope can say anything given `current`. A store with no
    /// session yet can only offer ``all``, and a session that never named its
    /// optimization level can't be compared against others by it.
    func resolvable(current: LogSession?) -> Bool {
        switch self {
            case .all: true
            case .currentSession: current != nil
            case .sameOptimizationLevel: current?.attributes[.optimizationLevel] != nil
        }
    }
}
