import CodeGraphModel
import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// `Edge` is also a SwiftUI type, so use a distinct alias for the model's edge
/// in the view layer (which imports SwiftUI) to avoid the ambiguity.
typealias GraphEdge = CodeGraphModel.Edge

/// A member of a type, flattened for display as a row inside the owner's chip
/// (so members no longer float as their own nodes). `typeName` is the member's
/// declared type when we can recover it (stored properties, via `propertyType`).
struct MemberRow: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: NodeKind
    let typeName: String?
}

/// Drives the canvas: which nodes/edges are visible, where they sit, what's
/// selected/expanded, and re-running the layout when any of that changes.
@MainActor
@Observable
final class GraphViewModel {
    let graph: CodeGraph

    private(set) var nodesByID: [String: Node]
    private let childrenByParent: [String: [Node]]
    private let outgoingByID: [String: [GraphEdge]]
    private let incomingByID: [String: [GraphEdge]]
    /// Members flattened per owning type, precomputed once (the graph is fixed),
    /// ordered for display and annotated with the property's type where known.
    private let memberRowsByType: [String: [MemberRow]]

    /// Filters (a fuller filter UI lands in the next step; these defaults give a
    /// readable first view: first-party types, members collapsed).
    var showExternal = false {
        didSet { invalidate() }
    }

    var showModules = false {
        didSet { invalidate() }
    }

    var showTests = true {
        didSet { invalidate() }
    }

    var includedEdgeKinds: Set<EdgeKind> = GraphViewModel
        .defaultEdgeKinds
    {
        didSet { invalidate() }
    }

    var includedNodeKinds: Set<NodeKind> = GraphViewModel.filterableKinds {
        didSet { invalidate() }
    }

    var hiddenModules: Set<String> = [] {
        didSet { invalidate() }
    }

    var nameQuery = "" {
        didSet { invalidate() }
    }

    /// When set, only the focus root and nodes within `focusDepth` hops of it
    /// (over the included edges) are shown.
    private(set) var focusRoot: String?
    var focusDepth = 1 {
        didSet { if focusRoot != nil { invalidate() } }
    }

    /// A readable starting set: the classic "is-a" edges plus the two most
    /// informative data-flow kinds. Membership/override are now shown *inside*
    /// the chip (so `.member` never reaches the canvas); the rest are opt-in.
    nonisolated static let defaultEdgeKinds: Set<EdgeKind> = [
        .inheritance,
        .conformance,
        .propertyType,
        .construction,
    ]

    /// Edge kinds the filter UI can toggle. `.member` is excluded — containment
    /// is drawn as rows in the type's chip, never as an edge on the canvas.
    nonisolated static let filterableEdgeKinds: [EdgeKind] = EdgeKind.allCases
        .filter { $0 != .member }

    /// Primary (non-member, non-module) node kinds the kind filter governs.
    nonisolated static let filterableKinds: Set<NodeKind> = [
        .class,
        .struct,
        .enum,
        .protocol,
        .actor,
        .extension,
        .typeAlias,
        .associatedType,
        .function,
    ]

    private(set) var expanded: Set<String> = []
    var selection: String? {
        didSet { recomputeSelectionNeighbors() }
    }

    /// Ids one edge away from the current selection, precomputed on selection
    /// change so the canvas can dim non-neighbors in O(1) per node instead of
    /// rescanning the selection's incident edges for every chip each render.
    private(set) var selectionNeighbors: Set<String> = []

    /// Drives the inspector presentation off the selection so the selection
    /// stays the single source of truth (no closure-based bindings in views).
    var isInspectorPresented: Bool {
        get { selection != nil }
        set { if !newValue { selection = nil } }
    }

    private(set) var positions: [String: CGPoint] = [:]
    private(set) var pinned: [String: CGPoint] = [:]
    private(set) var isLayingOut = false

    private(set) var visibleNodes: [Node] = []
    private(set) var visibleEdges: [GraphEdge] = []
    private var visibleIDs: Set<String> = []

    let allModuleNames: [String]
    let canvasSize = CGSize(width: 2800, height: 2000)
    private let engine = LayoutEngine()
    private var layoutTask: Task<Void, Never>?

    private let persistence: ViewerPersistence
    private var record = ViewerRecord()
    private(set) var savedViews: [SavedView] = []
    /// Suppresses relayout/persist side effects while a batch of state is being
    /// applied (restore / apply saved view).
    private var isBatching = false
    private var saveTask: Task<Void, Never>?
    /// Coalesces the bursty relayouts that filter/search changes would otherwise
    /// fire on every keystroke or toggle.
    private var relayoutDebounce: Task<Void, Never>?
    /// Bumped per scheduled layout so only the newest task applies its result
    /// and owns `isLayingOut` — a superseded (cancelled) task bows out without
    /// leaving the settling indicator stuck on.
    private var layoutGeneration = 0

    init(graph: CodeGraph, persistence: ViewerPersistence = ViewerPersistence()) {
        self.graph = graph
        self.persistence = persistence
        var byID = [String: Node](minimumCapacity: graph.nodes.count)
        var children = [String: [Node]]()
        for node in graph.nodes {
            byID[node.id] = node
        }
        for node in graph.nodes where node.kind.isMember {
            if let parent = node.parentID {
                children[parent, default: []].append(node)
            }
        }
        var outgoing = [String: [GraphEdge]]()
        var incoming = [String: [GraphEdge]]()
        for edge in graph.edges {
            outgoing[edge.source, default: []].append(edge)
            incoming[edge.target, default: []].append(edge)
        }
        memberRowsByType = Self.flattenMembers(children: children, outgoing: outgoing, byID: byID)
        nodesByID = byID
        childrenByParent = children
        outgoingByID = outgoing
        incomingByID = incoming
        allModuleNames = Set(graph.nodes.map(\.module)).sorted()
        record = persistence.load(repoPath: graph.repoPath)
        savedViews = record.savedViews
        apply(record.current)
        rebuildVisible()
    }

    // MARK: - Lookups

    func node(_ id: String) -> Node? {
        nodesByID[id]
    }

    func position(_ id: String) -> CGPoint? {
        positions[id]
    }

    func outgoing(_ id: String) -> [GraphEdge] {
        outgoingByID[id] ?? []
    }

    func incoming(_ id: String) -> [GraphEdge] {
        incomingByID[id] ?? []
    }

    func memberCount(_ id: String) -> Int {
        childrenByParent[id]?.count ?? 0
    }

    /// The member rows rendered inside a type's chip (empty for non-types).
    func memberRows(_ id: String) -> [MemberRow] {
        memberRowsByType[id] ?? []
    }

    /// The chip's drawn footprint, so the layout reserves the right space and
    /// keeps whole boxes — not just their centers — from overlapping.
    func chipSize(_ id: String) -> CGSize {
        guard let node = nodesByID[id] else {
            return CGSize(width: ChipMetrics.minWidth, height: ChipMetrics.headerHeight)
        }
        return ChipMetrics.size(name: node.name, rows: memberRows(id), expanded: isExpanded(id))
    }

    /// Flatten each type's members into display rows, ordered data-first
    /// (cases/properties before initializers/methods) and annotated with the
    /// property type recovered from the owner's `propertyType` edges.
    private static func flattenMembers(
        children: [String: [Node]],
        outgoing: [String: [GraphEdge]],
        byID: [String: Node],
    ) -> [String: [MemberRow]] {
        var result = [String: [MemberRow]](minimumCapacity: children.count)
        for (parent, members) in children {
            var typeByMember = [String: String]()
            for edge in outgoing[parent] ?? [] where edge.kind == .propertyType {
                guard let via = edge.viaMemberID,
                      let name = byID[edge.target]?.name else { continue }
                typeByMember[via] = name
            }
            result[parent] = members
                .sorted(by: memberOrder)
                .map { MemberRow(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.kind,
                    typeName: typeByMember[$0.id],
                ) }
        }
        return result
    }

    /// Group rank then declaration line then name, so members read like a UML
    /// box: stored data up top, behavior below, stable within each group.
    private static func memberOrder(_ a: Node, _ b: Node) -> Bool {
        let groupA = memberGroupRank(a.kind)
        let groupB = memberGroupRank(b.kind)
        if groupA != groupB { return groupA < groupB }
        let lineA = a.line ?? .max
        let lineB = b.line ?? .max
        if lineA != lineB { return lineA < lineB }
        return a.name < b.name
    }

    private static func memberGroupRank(_ kind: NodeKind) -> Int {
        switch kind {
            case .enumCase: 0
            case .property: 1
            case .initializer: 2
            case .method, .subscript: 3
            case .class, .struct, .enum, .protocol, .actor, .extension, .typeAlias,
                 .associatedType, .function, .module, .other: 4
        }
    }

    func isExpanded(_ id: String) -> Bool {
        expanded.contains(id)
    }

    func isPinned(_ id: String) -> Bool {
        pinned[id] != nil
    }

    // MARK: - Interaction

    func select(_ id: String?) {
        selection = id
    }

    private func recomputeSelectionNeighbors() {
        guard let id = selection else {
            selectionNeighbors = []
            return
        }
        var neighbors = Set<String>()
        for edge in outgoingByID[id] ?? [] {
            neighbors.insert(edge.target)
        }
        for edge in incomingByID[id] ?? [] {
            neighbors.insert(edge.source)
        }
        selectionNeighbors = neighbors
    }

    func toggleExpanded(_ id: String) {
        guard memberCount(id) > 0 else { return }
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
        invalidate()
    }

    /// Finish a drag: pin the node where it landed and re-settle the rest.
    func endDrag(_ id: String, at point: CGPoint) {
        positions[id] = point
        pinned[id] = point
        relayout()
        scheduleSave()
    }

    func unpin(_ id: String) {
        pinned.removeValue(forKey: id)
        relayout()
        scheduleSave()
    }

    func unpinAll() {
        pinned.removeAll()
        relayout()
        scheduleSave()
    }

    // MARK: - Persistence & saved views

    func saveCurrentView(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        record.savedViews.append(SavedView(name: trimmed, state: captureState()))
        savedViews = record.savedViews
        persistNow()
    }

    func applyView(_ view: SavedView) {
        apply(view.state)
        rebuildVisible()
        relayout()
        scheduleSave()
    }

    func deleteView(_ view: SavedView) {
        record.savedViews.removeAll { $0.id == view.id }
        savedViews = record.savedViews
        persistNow()
    }

    /// Apply a persisted state to the current graph, dropping references to
    /// symbols that no longer exist (reconciliation after a re-extract).
    private func apply(_ state: ViewerState) {
        isBatching = true
        pinned = state.pins.filter { nodesByID[$0.key] != nil }
        expanded = state.expanded.filter { nodesByID[$0] != nil }
        focusRoot = state.focusRoot.flatMap { nodesByID[$0] != nil ? $0 : nil }
        focusDepth = state.focusDepth
        showExternal = state.showExternal
        showTests = state.showTests
        showModules = state.showModules
        includedEdgeKinds = state.includedEdgeKinds
        includedNodeKinds = state.includedNodeKinds
        hiddenModules = state.hiddenModules
        nameQuery = state.nameQuery
        isBatching = false
    }

    private func captureState() -> ViewerState {
        ViewerState(
            pins: pinned,
            expanded: expanded,
            focusRoot: focusRoot,
            focusDepth: focusDepth,
            showExternal: showExternal,
            showTests: showTests,
            showModules: showModules,
            includedEdgeKinds: includedEdgeKinds,
            includedNodeKinds: includedNodeKinds,
            hiddenModules: hiddenModules,
            nameQuery: nameQuery,
        )
    }

    private func scheduleSave() {
        guard !isBatching else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        record.current = captureState()
        persistence.save(record, repoPath: graph.repoPath)
    }

    // MARK: - Filtering

    var isFocused: Bool {
        focusRoot != nil
    }

    var focusName: String? {
        focusRoot.flatMap { nodesByID[$0]?.name }
    }

    func focus(on id: String) {
        focusRoot = id
        invalidate()
    }

    func clearFocus() {
        focusRoot = nil
        invalidate()
    }

    func toggleEdgeKind(_ kind: EdgeKind) {
        if includedEdgeKinds.contains(kind) {
            includedEdgeKinds.remove(kind)
        } else {
            includedEdgeKinds.insert(kind)
        }
    }

    func toggleNodeKind(_ kind: NodeKind) {
        if includedNodeKinds.contains(kind) {
            includedNodeKinds.remove(kind)
        } else {
            includedNodeKinds.insert(kind)
        }
    }

    func toggleModuleHidden(_ module: String) {
        if hiddenModules.contains(module) {
            hiddenModules.remove(module)
        } else {
            hiddenModules.insert(module)
        }
    }

    func resetFilters() {
        showExternal = false
        showTests = true
        showModules = false
        includedEdgeKinds = Self.defaultEdgeKinds
        includedNodeKinds = Self.filterableKinds
        hiddenModules = []
        nameQuery = ""
        focusRoot = nil
        focusDepth = 1
        invalidate()
    }

    // MARK: - Visibility

    private func passesFilters(_ node: Node) -> Bool {
        guard !hiddenModules.contains(node.module), matchesOrigin(node) else { return false }
        if node.kind == .module {
            return showModules && matchesQuery(node)
        }
        if node.kind.isMember {
            // Members render as rows inside their owner's chip, never as nodes.
            return false
        }
        if Self.filterableKinds.contains(node.kind), !includedNodeKinds.contains(node.kind) {
            return false
        }
        return matchesQuery(node)
    }

    private func matchesOrigin(_ node: Node) -> Bool {
        switch node.origin {
            case .firstParty: true
            case .external: showExternal
            case .test: showTests
        }
    }

    private func matchesQuery(_ node: Node) -> Bool {
        guard !nameQuery.isEmpty else { return true }
        return node.name.localizedCaseInsensitiveContains(nameQuery)
    }

    private func rebuildVisible() {
        let allowed = graph.nodes.filter(passesFilters)
        var ids = Set(allowed.map(\.id))
        var nodes = allowed
        if let root = focusRoot {
            ids = focusNeighborhood(root: root, depth: focusDepth, allowed: ids)
            nodes = graph.nodes.filter { ids.contains($0.id) }
        }
        visibleNodes = nodes
        visibleIDs = ids
        visibleEdges = canvasEdges(visible: ids)
        seedMissingPositions()
    }

    /// The edges the canvas draws: every edge endpoint projected to its owning
    /// type (members live inside chips now), dropping membership edges and any
    /// edge that collapses onto a single type, then de-duplicated so a type pair
    /// shows one line per kind regardless of how many members route through it.
    private func canvasEdges(visible ids: Set<String>) -> [GraphEdge] {
        var seen = Set<String>()
        var result = [GraphEdge]()
        for edge in graph.edges {
            guard edge.kind != .member, includedEdgeKinds.contains(edge.kind) else { continue }
            let source = owningType(edge.source)
            let target = owningType(edge.target)
            guard source != target, ids.contains(source), ids.contains(target) else { continue }
            guard seen.insert("\(source)|\(target)|\(edge.kind.rawValue)").inserted
            else { continue }
            if source == edge.source, target == edge.target {
                result.append(edge)
            } else {
                result.append(GraphEdge(
                    id: "\(source)|\(target)|\(edge.kind.rawValue)",
                    source: source,
                    target: target,
                    kind: edge.kind,
                    viaMemberID: edge.viaMemberID,
                    count: edge.count,
                ))
            }
        }
        return result
    }

    /// The type a node belongs on the canvas as: a member resolves to its
    /// enclosing type; everything else is itself.
    private func owningType(_ id: String) -> String {
        guard let node = nodesByID[id], node.kind.isMember, let parent = node.parentID
        else { return id }
        return parent
    }

    /// Give nodes that just became visible a provisional position so they paint
    /// immediately instead of vanishing until the debounced relayout finishes
    /// (the canvas only draws nodes present in `positions`). Skipped on the cold
    /// first layout — there the settling pass places the whole graph at once.
    private func seedMissingPositions() {
        guard !positions.isEmpty else { return }
        let missing = visibleNodes.filter { positions[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let centroids = moduleCentroids()
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        for node in missing {
            positions[node.id] = neighborCentroid(for: node)
                ?? centroids[node.module]
                ?? center
        }
    }

    /// Average position of a node's already-placed neighbors, so an expanded
    /// type's members land on top of it and fan out from there.
    private func neighborCentroid(for node: Node) -> CGPoint? {
        var sum = CGPoint.zero
        var count = 0
        for edge in outgoingByID[node.id] ?? [] {
            if let point = positions[edge.target] {
                sum.x += point.x
                sum.y += point.y
                count += 1
            }
        }
        for edge in incomingByID[node.id] ?? [] {
            if let point = positions[edge.source] {
                sum.x += point.x
                sum.y += point.y
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return CGPoint(x: sum.x / Double(count), y: sum.y / Double(count))
    }

    /// Centroid of each module's already-placed visible nodes, for seeding a new
    /// node that has no placed neighbor to anchor against.
    private func moduleCentroids() -> [String: CGPoint] {
        var sums = [String: CGPoint]()
        var counts = [String: Int]()
        for node in visibleNodes {
            guard let point = positions[node.id] else { continue }
            sums[node.module, default: .zero].x += point.x
            sums[node.module, default: .zero].y += point.y
            counts[node.module, default: 0] += 1
        }
        return sums.reduce(into: [:]) { result, entry in
            let count = counts[entry.key] ?? 1
            result[entry.key] = CGPoint(
                x: entry.value.x / Double(count),
                y: entry.value.y / Double(count),
            )
        }
    }

    /// Breadth-first set of node ids reachable from `root` within `depth` hops,
    /// traversing only included edges into allowed nodes (root always included).
    private func focusNeighborhood(root: String, depth: Int, allowed: Set<String>) -> Set<String> {
        var visited: Set<String> = [root]
        var frontier = [root]
        for _ in 0 ..< max(depth, 0) {
            var next = [String]()
            for id in frontier {
                for edge in outgoingByID[id] ?? [] where includedEdgeKinds.contains(edge.kind)
                    && allowed.contains(edge.target) && !visited.contains(edge.target)
                {
                    visited.insert(edge.target)
                    next.append(edge.target)
                }
                for edge in incomingByID[id] ?? [] where includedEdgeKinds.contains(edge.kind)
                    && allowed.contains(edge.source) && !visited.contains(edge.source)
                {
                    visited.insert(edge.source)
                    next.append(edge.source)
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return visited
    }

    /// Recompute the visible set immediately (so nodes appear/disappear without
    /// lag) but coalesce the expensive relayout so a burst of filter/search
    /// changes settles once, not once per keystroke.
    func invalidate() {
        guard !isBatching else { return }
        rebuildVisible()
        scheduleRelayout()
        scheduleSave()
    }

    // MARK: - Layout

    private func scheduleRelayout() {
        relayoutDebounce?.cancel()
        relayoutDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.relayout()
        }
    }

    func relayout() {
        relayoutDebounce?.cancel()
        layoutTask?.cancel()
        let input = LayoutInput(
            nodes: visibleNodes.map { .init(id: $0.id, module: $0.module, size: chipSize($0.id)) },
            edges: visibleEdges.map {
                .init(
                    source: $0.source,
                    target: $0.target,
                    weight: $0.kind.isStructural ? 2.0 : 1.0,
                )
            },
            pinned: pinned.filter { visibleIDs.contains($0.key) },
            initial: positions.filter { visibleIDs.contains($0.key) },
            size: canvasSize,
        )
        isLayingOut = true
        layoutGeneration &+= 1
        let generation = layoutGeneration
        layoutTask = Task { [engine, weak self] in
            let result = await engine.layout(input)
            guard let self, generation == layoutGeneration else { return }
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.35)) {
                    positions = result
                }
            }
            // Only the newest layout reaches here; clear the flag whether it
            // finished or was cancelled so a cancelled final task can't leave
            // the settling indicator stuck on.
            isLayingOut = false
        }
    }
}
