import Foundation
import Observation
import PeriscopeCore

/// One node in the span tree: a begin/end span pair, nested under the span
/// whose lifetime encloses it. `children` is `nil` for a leaf so the outline
/// shows no disclosure control.
struct SpanNode: Identifiable, Hashable {
    let id: SpanID
    let name: String
    /// The stored `SpanBegan` event — the drill-in target.
    let began: StoredLogEvent
    /// When the span began — the row's timestamp.
    let begin: Date
    /// Whether the span is still running and, once it isn't, everything its end
    /// had to say.
    let outcome: Outcome
    var children: [SpanNode]?

    /// Whether the span is still running and, once it isn't, everything its end
    /// had to say.
    ///
    /// One value rather than parallel `ended` / `exitMode` / `duration`
    /// optionals: with those, a span whose end payload failed to decode rendered
    /// an exit chip beside a "running" duration — the one reading that cannot be
    /// true, since the exit came from an indexed column while the duration came
    /// from the payload. Here a span that ended can only describe itself as
    /// ended.
    enum Outcome: Hashable {
        /// No `SpanEnded` has been seen for this span.
        case open
        case ended(Ended)

        /// A span's end: the event, the exit its row recorded, and how long the
        /// span took.
        struct Ended: Hashable {
            /// The stored `SpanEnded` event.
            let event: StoredLogEvent
            /// The exit from the end row's indexed column, or `nil` when the row
            /// carries none.
            let mode: SpanExit.Mode?
            let timing: Timing
        }

        /// How long an ended span took, as far as its end could say.
        enum Timing: Hashable {
            /// The duration the end recorded.
            case measured(Duration)
            /// The end recorded none. An orphan closed by the relaunch sweep has
            /// no duration to record — the process died at an unknown point.
            case unmeasured
            /// The end's payload wouldn't decode, so the duration is unknown
            /// rather than absent. Kept distinct so a corrupt row reads as
            /// corrupt instead of as a span that never measured anything.
            case undecodable
        }
    }

    var isOpen: Bool {
        if case .open = outcome { return true }
        return false
    }

    /// The stored `SpanEnded` event, or `nil` while the span is still open.
    var ended: StoredLogEvent? {
        if case let .ended(ended) = outcome { return ended.event }
        return nil
    }

    /// How the span ended, or `nil` while open (or when the end row recorded no
    /// exit).
    var exitMode: SpanExit.Mode? {
        if case let .ended(ended) = outcome { return ended.mode }
        return nil
    }

    /// The measured duration, or `nil` for an open span and for an end that
    /// couldn't produce one. Callers that must *distinguish* those — anything
    /// rendering the span — switch on ``outcome`` instead.
    var measuredDuration: Duration? {
        guard case let .ended(ended) = outcome, case let .measured(duration) = ended.timing else {
            return nil
        }
        return duration
    }
}

/// Drives ``SpanTreeView``: pairs the store's `SpanBegan`/`SpanEnded` events by
/// `SpanID` and nests them into a trace-style tree by time containment (a span
/// whose lifetime falls inside another's becomes its child), refreshing when
/// the store commits.
@MainActor
@Observable
final class SpanTreeModel {
    /// One load's outcome — loading, the span forest, or an honest failure.
    enum LoadState {
        case loading
        case loaded([SpanNode])
        case failed(String)
    }

    /// Exposed so the hosting view can detect a store swap and rebuild.
    let store: PeriscopeStore

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]

    /// Every span begin/end seen so far, accumulated across refreshes so each
    /// commit only fetches the span events appended since the last one. A
    /// span's end typically lands in a later commit than its begin; both get
    /// paired here once seen.
    @ObservationIgnored private var begins: [StoredLogEvent] = []
    @ObservationIgnored private var ends: [StoredLogEvent] = []
    /// The highest event ``StoredLogEvent/sequence`` merged so far — the
    /// cursor the next refresh queries past. `nil` means nothing loaded yet,
    /// so the first fetch reads all span events.
    @ObservationIgnored private var watermark: Int?

    init(store: PeriscopeStore) {
        self.store = store
    }

    /// Initial load plus live refresh — run from `.task` so leaving the
    /// screen cancels the stream. The changes stream is acquired *before* the
    /// initial load so a commit landing mid-load can't fall into the gap
    /// between loading and subscribing.
    func run() async {
        let changes = await store.changes()
        await load()
        for await _ in changes {
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Fetch only the span begins/ends appended since the last load (via the
    /// `afterSequence` cursor), fold them into the accumulated pairs, and
    /// rebuild the tree. The over-the-wire read is bounded by what a single
    /// commit added rather than every span the store has ever recorded.
    func load() async {
        do {
            var beginQuery = LogQuery()
            beginQuery.eventName = SpanBegan.eventName
            beginQuery.afterSequence = watermark
            var endQuery = LogQuery()
            endQuery.eventName = SpanEnded.eventName
            endQuery.afterSequence = watermark
            let newBegins = try await store.events(matching: beginQuery)
            let newEnds = try await store.events(matching: endQuery)
            let scopeList = try await store.scopes()
            merge(begins: newBegins, ends: newEnds)
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })
            state = .loaded(Self.buildTree(begins: begins, ends: ends))
        } catch {
            PeriscopeToolsLog.failures.error(
                "Span tree could not read the store: \(error, privacy: .public)",
            )
            state = .failed(String(describing: error))
        }
    }

    /// Append the span events strictly past the watermark and advance it.
    /// Filtering here (not just in the query) keeps the merge idempotent: a
    /// refresh that re-runs over events already accumulated — e.g. a
    /// re-`run()` after the view reappears — skips them rather than
    /// double-listing a span.
    private func merge(begins newBegins: [StoredLogEvent], ends newEnds: [StoredLogEvent]) {
        let floor = watermark ?? Int.min
        begins.append(contentsOf: newBegins.filter { $0.sequence > floor })
        ends.append(contentsOf: newEnds.filter { $0.sequence > floor })
        if let highest = (newBegins + newEnds).map(\.sequence).max() {
            watermark = max(watermark ?? highest, highest)
        }
    }

    func scopePath(for event: StoredLogEvent) -> String {
        guard let primary = event.primaryScope else { return "" }
        return LogScope.ancestry(of: primary) { scopes[$0] }
            .map(\.name)
            .joined(separator: " / ")
    }

    /// Pair begins with their ends and nest by time containment. Spans sort by
    /// begin (earliest first; longer-lived first on ties) and a running stack
    /// parents each span to the innermost still-open container — the standard
    /// interval nesting, with open spans treated as ending in the far future.
    static func buildTree(begins: [StoredLogEvent], ends: [StoredLogEvent]) -> [SpanNode] {
        var endBySpan: [SpanID: StoredLogEvent] = [:]
        for ended in ends {
            guard let id = ended.spanID else { continue }
            endBySpan[id] = ended
        }

        struct Building {
            let id: SpanID
            let name: String
            let began: StoredLogEvent
            let begin: Date
            let outcome: SpanNode.Outcome
            let effectiveEnd: Date
        }

        let buildings: [Building] = begins.compactMap { began in
            guard let id = began.spanID else { return nil }
            let ended = endBySpan[id]
            return Building(
                id: id,
                name: spanName(from: began),
                began: began,
                begin: began.date,
                outcome: ended.map { outcome(for: $0) } ?? .open,
                effectiveEnd: ended?.date ?? .distantFuture,
            )
        }

        let sorted = buildings.sorted { lhs, rhs in
            if lhs.begin != rhs.begin { return lhs.begin < rhs.begin }
            return lhs.effectiveEnd > rhs.effectiveEnd
        }

        final class MutableNode {
            let building: Building
            var children: [MutableNode] = []
            init(_ building: Building) {
                self.building = building
            }

            func freeze() -> SpanNode {
                let childNodes = children.map { $0.freeze() }
                return SpanNode(
                    id: building.id,
                    name: building.name,
                    began: building.began,
                    begin: building.begin,
                    outcome: building.outcome,
                    children: childNodes.isEmpty ? nil : childNodes,
                )
            }
        }

        var roots: [MutableNode] = []
        var stack: [MutableNode] = []
        for building in sorted {
            while let top = stack.last, top.building.effectiveEnd <= building.begin {
                stack.removeLast()
            }
            let node = MutableNode(building)
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }
        return roots.map { $0.freeze() }
    }

    /// The span's name from its began payload, falling back to the row's
    /// message with the span-began marker stripped. A decode failure here is
    /// cosmetic — the tree still shows the span — but it's logged, since a
    /// payload written by `JSONEncoder` failing to decode means on-disk
    /// corruption.
    private static func spanName(from began: StoredLogEvent) -> String {
        do {
            return try began.decode(SpanBegan.self).name
        } catch {
            PeriscopeToolsLog.failures.warning(
                """
                Span tree could not decode the SpanBegan payload for span \
                \(began.spanID?.rawValue.uuidString ?? "unknown", privacy: .public); \
                naming it from its message: \(error, privacy: .public)
                """,
            )
            return began.message.replacingOccurrences(of: "▶ ", with: "")
        }
    }

    /// The end's outcome: its recorded exit plus what its payload could say
    /// about the duration. An undecodable payload is reported as such rather
    /// than as a missing duration, so the row can't read as still running.
    private static func outcome(for ended: StoredLogEvent) -> SpanNode.Outcome {
        let timing: SpanNode.Outcome.Timing
        do {
            let decoded = try ended.decode(SpanEnded.self)
            timing = decoded.duration.map { .measured($0) } ?? .unmeasured
        } catch {
            PeriscopeToolsLog.failures.warning(
                """
                Span tree could not decode the SpanEnded payload for span \
                \(ended.spanID?.rawValue.uuidString ?? "unknown", privacy: .public); \
                its duration is unknown: \(error, privacy: .public)
                """,
            )
            timing = .undecodable
        }
        return .ended(
            SpanNode.Outcome.Ended(event: ended, mode: ended.spanExitMode, timing: timing),
        )
    }
}
