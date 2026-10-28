import Foundation
import Observation
import PeriscopeCore

/// The p50/p90/p95/p99 of a set of span durations, computed by the nearest-rank
/// method: each reported value is an *actual* observed duration (no
/// interpolation), so the numbers can't invent a duration no span ever took.
struct SpanDurationPercentiles: Equatable {
    let p50: Duration
    let p90: Duration
    let p95: Duration
    let p99: Duration

    /// Nearest-rank percentiles over `durations`; `nil` when the input is
    /// empty (e.g. every recorded instance was orphaned and so lacks a measured
    /// duration). The rank for fraction *f* over *n* samples is `ceil(f · n)`,
    /// clamped into `1...n`, selecting a real sample from the sorted set.
    init?(durations: [Duration]) {
        guard !durations.isEmpty else { return nil }
        let sorted = durations.sorted()
        func percentile(_ fraction: Double) -> Duration {
            let rank = Int((fraction * Double(sorted.count)).rounded(.up))
            let index = min(max(rank, 1), sorted.count) - 1
            return sorted[index]
        }
        p50 = percentile(0.5)
        p90 = percentile(0.9)
        p95 = percentile(0.95)
        p99 = percentile(0.99)
    }
}

/// A span kind's name, and whether it's the recorded one.
///
/// A `SpanEnded` payload that won't decode can't give up its `name`, and the
/// row's message is close enough to group by — but grouping by it silently
/// mints a bucket that looks like a real span kind. Naming the two cases apart
/// keeps a corrupt row's bucket labelled as what it is.
enum SpanKindName: Hashable {
    /// Decoded from the end's payload.
    case recorded(String)
    /// The end's payload wouldn't decode, so this is its message with the
    /// span-ended marker stripped.
    case recovered(String)

    var text: String {
        switch self {
            case let .recorded(text), let .recovered(text): text
        }
    }

    /// Whether the name came from the message rather than the payload.
    var isRecovered: Bool {
        if case .recovered = self { return true }
        return false
    }
}

/// Aggregate timing for one span *kind* — every closed span sharing a
/// `SpanEnded.name`: how many instances closed and their duration percentiles,
/// plus the underlying `SpanEnded` events (newest first) the row drills into.
struct SpanKindSummary: Identifiable {
    var id: SpanKindName {
        kind
    }

    let kind: SpanKindName
    /// Duration percentiles across the instances that recorded a duration, or
    /// `nil` when none did (all orphaned).
    let percentiles: SpanDurationPercentiles?
    /// The closed-span (`SpanEnded`) events for this kind, newest first — the
    /// drill-in list.
    let events: [StoredLogEvent]

    /// Number of closed instances recorded for this kind (all ends seen,
    /// including any orphaned ones without a duration).
    var count: Int {
        events.count
    }
}

/// Drives ``SpanHistoryView``: reads the store's closed spans (`SpanEnded`
/// events), groups them by kind (`SpanEnded.name`), and summarizes each kind's
/// instance count and duration percentiles, refreshing when the store commits.
///
/// Only *closed* spans appear — open spans have no end event and so no measured
/// duration. Distinct from ``SpanTreeModel`` (which nests begin/end pairs into a
/// trace tree); this aggregates ends by kind for a timing overview.
///
/// A reading is scoped by build (``scope``): pooling an unoptimized build's
/// durations with an optimized one's produces percentiles that describe neither.
@MainActor
@Observable
final class SpanHistoryModel {
    /// One load's outcome — loading, the per-kind summaries, or an honest
    /// failure (surfaced in the UI rather than swallowed).
    enum LoadState {
        case loading
        case loaded([SpanKindSummary])
        case failed(String)
    }

    /// Exposed so the hosting view can detect a store swap and rebuild.
    let store: PeriscopeStore

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]

    /// Which builds the reading covers. Setting it re-derives the summaries
    /// from the ends already fetched — narrowing a reading is a filter over
    /// accumulated events, never a refetch.
    var scope: SpanHistoryScope = .all {
        didSet {
            guard oldValue != scope else { return }
            rebuild()
        }
    }

    /// The scopes worth offering, given what the store's sessions can say —
    /// always at least ``SpanHistoryScope/all``.
    private(set) var availableScopes: [SpanHistoryScope] = [.all]

    /// Every `SpanEnded` seen so far, accumulated across refreshes so each
    /// commit only fetches the ends appended since the last one.
    @ObservationIgnored private var ends: [StoredLogEvent] = []
    /// The highest event ``StoredLogEvent/sequence`` merged so far — the cursor
    /// the next refresh queries past. `nil` means nothing loaded yet.
    @ObservationIgnored private var watermark: Int?
    /// Every recorded session, and the one running now — what ``scope`` filters
    /// events by. Refreshed each load, since a session can start mid-viewing.
    @ObservationIgnored private var sessions: [LogSession] = []
    @ObservationIgnored private var currentSession: LogSession?

    init(store: PeriscopeStore) {
        self.store = store
    }

    /// Distinct sessions among the ends the active scope admits — the
    /// sessions actually *contributing* durations, not merely the ones the
    /// scope would accept. A session that recorded no spans padding the
    /// count would overstate how broad a reading is.
    private(set) var contributingSessionCount = 0

    /// One line naming what the percentiles cover, so a reading can't be
    /// mistaken for a different one — the count is of sessions contributing
    /// ends, which is what makes "same optimization level" concrete.
    var scopeSummary: String {
        let count = contributingSessionCount
        let sessionCount = "\(count) session\(count == 1 ? "" : "s")"
        switch scope {
            case .all:
                return "All builds · \(sessionCount)"
            case .currentSession:
                return "This session only"
            case .sameOptimizationLevel:
                let level = currentSession?.attributes[.optimizationLevel] ?? "unstated"
                return "Built at \(level) · \(sessionCount)"
        }
    }

    /// The empty-state line for the active scope. Separate from
    /// ``scopeSummary`` so the view never has to bend a summary into a
    /// sentence — lowercasing one would garble case-sensitive values like
    /// `-Onone`.
    var emptyStateDescription: String {
        switch scope {
            case .all:
                return "No closed spans have been recorded yet."
            case .currentSession:
                return "No closed spans from this session."
            case .sameOptimizationLevel:
                let level = currentSession?.attributes[.optimizationLevel] ?? "unstated"
                return "No closed spans from builds at \(level)."
        }
    }

    /// Initial load plus live refresh — run from `.task` so leaving the screen
    /// cancels the stream. The changes stream is acquired *before* the initial
    /// load so a commit landing mid-load can't fall into the gap between
    /// loading and subscribing.
    func run() async {
        let changes = await store.changes()
        await load()
        for await _ in changes {
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Fetch only the `SpanEnded` events appended since the last load (via the
    /// `afterSequence` cursor), fold them into the accumulated ends, and rebuild
    /// the per-kind summaries. The over-the-wire read is bounded by what a
    /// single commit added rather than every span the store has ever recorded.
    func load() async {
        do {
            var query = LogQuery()
            query.eventName = SpanEnded.eventName
            query.afterSequence = watermark
            let newEnds = try await store.events(matching: query)
            let scopeList = try await store.scopes()
            let sessionList = try await store.sessions()
            let current = await store.currentSession
            merge(ends: newEnds)
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })
            adopt(sessions: sessionList, current: current)
            present()
        } catch {
            PeriscopeToolsLog.failures.error(
                "Span history could not read the store: \(error, privacy: .public)",
            )
            state = .failed(String(describing: error))
        }
    }

    /// Take the freshly read sessions and re-derive which scopes they can
    /// support, dropping the selection back to ``SpanHistoryScope/all`` if it
    /// no longer resolves — a reading must never keep a scope label it can't
    /// honor. (The store only gains sessions, so in practice this widens the
    /// options rather than narrowing them.)
    private func adopt(sessions: [LogSession], current: LogSession?) {
        self.sessions = sessions
        currentSession = current
        availableScopes = SpanHistoryScope.allCases.filter { $0.resolvable(current: current) }
        if !availableScopes.contains(scope) {
            scope = .all
        }
    }

    /// Re-derive the summaries from the accumulated ends under the current
    /// scope. Only meaningful once a load has succeeded: rebuilding out of
    /// `.loading` or `.failed` would present a reading as loaded that no
    /// completed load produced.
    private func rebuild() {
        guard case .loaded = state else { return }
        present()
    }

    /// Publish the scoped reading: the per-kind summaries and the count of
    /// sessions contributing to them, derived from the same set of ends so
    /// the header can't describe a different reading than the rows show.
    private func present() {
        let scoped = scopedEnds()
        contributingSessionCount = Set(scoped.map(\.sessionID)).count
        state = .loaded(Self.summaries(from: scoped))
    }

    /// The accumulated ends the active scope admits. ``SpanHistoryScope/all``
    /// short-circuits, so the default reading doesn't build a set or walk every
    /// event to include all of them.
    private func scopedEnds() -> [StoredLogEvent] {
        guard let admitted = scope.sessionIDs(in: sessions, current: currentSession) else {
            return ends
        }
        return ends.filter { admitted.contains($0.sessionID) }
    }

    /// Append the ends strictly past the watermark and advance it. Filtering
    /// here (not just in the query) keeps the merge idempotent: a refresh that
    /// re-runs over ends already accumulated — e.g. a re-`run()` after the view
    /// reappears — skips them rather than double-counting a span.
    private func merge(ends newEnds: [StoredLogEvent]) {
        let floor = watermark ?? Int.min
        ends.append(contentsOf: newEnds.filter { $0.sequence > floor })
        if let highest = newEnds.map(\.sequence).max() {
            watermark = max(watermark ?? highest, highest)
        }
    }

    func scopePath(for event: StoredLogEvent) -> String {
        guard let primary = event.primaryScope else { return "" }
        return LogScope.ancestry(of: primary) { scopes[$0] }
            .map(\.name)
            .joined(separator: " / ")
    }

    /// Group the closed-span events by kind, compute each kind's duration
    /// percentiles, and order by instance count (busiest first; name breaks
    /// ties) so the most-recorded spans surface at the top. Each event is
    /// decoded once; an event whose payload can't be decoded groups under a
    /// ``SpanKindName/recovered(_:)`` name — it still appears, and the row says
    /// the name isn't the recorded one.
    static func summaries(from ends: [StoredLogEvent]) -> [SpanKindSummary] {
        struct Closed {
            let event: StoredLogEvent
            let kind: SpanKindName
            let duration: Duration?
        }

        let closed = ends.map { end -> Closed in
            do {
                let decoded = try end.decode(SpanEnded.self)
                return Closed(event: end, kind: .recorded(decoded.name), duration: decoded.duration)
            } catch {
                PeriscopeToolsLog.failures.warning(
                    """
                    Span history could not decode the SpanEnded payload for span \
                    \(end.spanID?.rawValue.uuidString ?? "unknown", privacy: .public); \
                    grouping it by its message: \(error, privacy: .public)
                    """,
                )
                // The name recovered from the message, not the raw message:
                // a message embeds the exit reason and duration, which vary
                // per instance and would fragment the kind into a bucket
                // per row.
                return Closed(
                    event: end,
                    kind: .recovered(SpanEnded.nameRecovered(
                        fromMessage: end.message,
                        exit: end.spanExitMode,
                    )),
                    duration: nil,
                )
            }
        }

        return Dictionary(grouping: closed, by: \.kind)
            .map { kind, group in
                let ordered = group.sorted { lhs, rhs in
                    if lhs.event.date != rhs.event.date { return lhs.event.date > rhs.event.date }
                    return lhs.event.sequence > rhs.event.sequence
                }
                return SpanKindSummary(
                    kind: kind,
                    percentiles: SpanDurationPercentiles(durations: ordered.compactMap(\.duration)),
                    events: ordered.map(\.event),
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.kind.text < rhs.kind.text
            }
    }
}
