import CodeGraphModel
import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// `Edge` is also a SwiftUI type, so use a distinct alias for the model's edge
/// in the view layer (which imports SwiftUI) to avoid the ambiguity.
typealias GraphEdge = CodeGraphModel.Edge

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

    var nameQuery = "" {
        didSet { invalidate() }
    }

    /// A readable starting set: the classic "is-a"/ownership edges plus the two
    /// most informative data-flow kinds. The rest are opt-in via filters.
    static let defaultEdgeKinds: Set<EdgeKind> = [
        .inheritance,
        .conformance,
        .propertyType,
        .construction,
        .member,
        .override,
    ]

    private(set) var expanded: Set<String> = []
    var selection: String?

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

    let canvasSize = CGSize(width: 2800, height: 2000)
    private let engine = LayoutEngine()
    private var layoutTask: Task<Void, Never>?

    init(graph: CodeGraph) {
        self.graph = graph
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
        nodesByID = byID
        childrenByParent = children
        outgoingByID = outgoing
        incomingByID = incoming
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

    func toggleExpanded(_ id: String) {
        guard memberCount(id) > 0 else { return }
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
        invalidate()
    }

    /// Live position update while dragging (no relayout).
    func drag(_ id: String, to point: CGPoint) {
        positions[id] = point
    }

    /// Finish a drag: pin the node where it landed and re-settle the rest.
    func endDrag(_ id: String, at point: CGPoint) {
        positions[id] = point
        pinned[id] = point
        relayout()
    }

    func unpin(_ id: String) {
        pinned.removeValue(forKey: id)
        relayout()
    }

    func unpinAll() {
        pinned.removeAll()
        relayout()
    }

    // MARK: - Visibility

    func isVisible(_ node: Node) -> Bool {
        if node.kind == .module {
            return showModules && matchesQuery(node) && matchesOrigin(node)
        }
        if node.kind.isMember {
            guard let parent = node.parentID, expanded.contains(parent) else { return false }
            return matchesOrigin(node)
        }
        return matchesQuery(node) && matchesOrigin(node)
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
        let nodes = graph.nodes.filter(isVisible)
        let ids = Set(nodes.map(\.id))
        let edges = graph.edges.filter {
            includedEdgeKinds.contains($0.kind) && ids.contains($0.source) && ids
                .contains($0.target)
        }
        visibleNodes = nodes
        visibleIDs = ids
        visibleEdges = edges
    }

    /// Recompute the visible set and re-run the layout.
    func invalidate() {
        rebuildVisible()
        relayout()
    }

    // MARK: - Layout

    func relayout() {
        layoutTask?.cancel()
        let input = LayoutInput(
            nodes: visibleNodes.map { .init(id: $0.id, module: $0.module) },
            edges: visibleEdges.map {
                .init(
                    source: $0.source,
                    target: $0.target,
                    weight: $0.kind.isStructural ? 2.0 : 1.0,
                )
            },
            pinned: pinned.filter { visibleIDs.contains($0.key) },
            size: canvasSize,
        )
        isLayingOut = true
        layoutTask = Task { [engine] in
            let result = await engine.layout(input)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                positions = result
            }
            isLayingOut = false
        }
    }
}
