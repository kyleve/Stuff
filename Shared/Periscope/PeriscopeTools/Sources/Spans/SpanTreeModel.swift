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
    /// The stored `SpanEnded` event, or `nil` while the span is still open.
    let ended: StoredLogEvent?
    /// Measured duration, when the end recorded one.
    let duration: Duration?
    /// How the span ended, or `nil` while open.
    let exitMode: SpanExit.Mode?
    /// When the span began — the row's timestamp.
    let begin: Date
    var children: [SpanNode]?

    var isOpen: Bool {
        ended == nil
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
    @ObservationIgnored private var generation = 0

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]

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

    func load() async {
        generation += 1
        let requested = generation
        do {
            var beginQuery = LogQuery()
            beginQuery.eventName = SpanBegan.eventName
            var endQuery = LogQuery()
            endQuery.eventName = SpanEnded.eventName
            let begins = try await store.events(matching: beginQuery)
            let ends = try await store.events(matching: endQuery)
            let scopeList = try await store.scopes()
            guard requested == generation else { return }
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })
            state = .loaded(Self.buildTree(begins: begins, ends: ends))
        } catch {
            guard requested == generation else { return }
            state = .failed(String(describing: error))
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
            let ended: StoredLogEvent?
            let duration: Duration?
            let exitMode: SpanExit.Mode?
            let begin: Date
            let effectiveEnd: Date
        }

        let buildings: [Building] = begins.compactMap { began in
            guard let id = began.spanID else { return nil }
            let ended = endBySpan[id]
            let name = (try? began.decode(SpanBegan.self))?.name
                ?? began.message.replacingOccurrences(of: "▶ ", with: "")
            let duration = ended.flatMap { try? $0.decode(SpanEnded.self) }?.duration
            return Building(
                id: id,
                name: name,
                began: began,
                ended: ended,
                duration: duration,
                exitMode: ended?.spanExitMode,
                begin: began.date,
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
                    ended: building.ended,
                    duration: building.duration,
                    exitMode: building.exitMode,
                    begin: building.begin,
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
}
