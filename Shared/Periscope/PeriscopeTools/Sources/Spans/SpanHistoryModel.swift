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

/// Aggregate timing for one span *kind* — every closed span sharing a
/// `SpanEnded.name`: how many instances closed and their duration percentiles,
/// plus the underlying `SpanEnded` events (newest first) the row drills into.
struct SpanKindSummary: Identifiable {
    var id: String {
        name
    }

    let name: String
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

    /// Every `SpanEnded` seen so far, accumulated across refreshes so each
    /// commit only fetches the ends appended since the last one.
    @ObservationIgnored private var ends: [StoredLogEvent] = []
    /// The highest event ``StoredLogEvent/sequence`` merged so far — the cursor
    /// the next refresh queries past. `nil` means nothing loaded yet.
    @ObservationIgnored private var watermark: Int?

    init(store: PeriscopeStore) {
        self.store = store
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
            merge(ends: newEnds)
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })
            state = .loaded(Self.summaries(from: ends))
        } catch {
            state = .failed(String(describing: error))
        }
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
    /// decoded once; the kind name falls back to the message when a payload
    /// can't be decoded (a corrupt row still groups rather than vanishing).
    static func summaries(from ends: [StoredLogEvent]) -> [SpanKindSummary] {
        struct Closed {
            let event: StoredLogEvent
            let name: String
            let duration: Duration?
        }

        let closed = ends.map { end -> Closed in
            let decoded = try? end.decode(SpanEnded.self)
            let name = decoded?.name ?? end.message.replacingOccurrences(of: "◀ ", with: "")
            return Closed(event: end, name: name, duration: decoded?.duration)
        }

        return Dictionary(grouping: closed, by: \.name)
            .map { name, group in
                let ordered = group.sorted { lhs, rhs in
                    if lhs.event.date != rhs.event.date { return lhs.event.date > rhs.event.date }
                    return lhs.event.sequence > rhs.event.sequence
                }
                return SpanKindSummary(
                    name: name,
                    percentiles: SpanDurationPercentiles(durations: ordered.compactMap(\.duration)),
                    events: ordered.map(\.event),
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name < rhs.name
            }
    }
}
