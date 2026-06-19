import CodeGraphModel
@testable import CodeGraphViewer
import CoreGraphics
import Foundation
import Testing

/// Filtering, focus, expansion, and persistence reconciliation are pure
/// functions of the loaded graph plus the current filter state, so they can be
/// exercised against a small hand-built graph with no UI or layout in play.
@MainActor
struct GraphViewModelTests {
    // MARK: - Fixture

    /// A deterministic graph spanning all three origins and a member, with both
    /// default-visible and opt-in edge kinds:
    ///
    ///     Tester ─construction▶ Alpha ─conformance▶ Proto ◀conformance─ Gamma
    ///                             │ │
    ///               propertyType  │ └─member▶ field
    ///                             ▼
    ///                            Beta
    ///     Alpha ─propertyType▶ ExtType (external)
    ///     Alpha ─reference▶ Beta            (opt-in kind)
    ///     Beta  ─paramOrReturnType▶ Gamma   (opt-in kind)
    private func makeGraph() -> CodeGraph {
        func node(
            _ id: String,
            _ kind: NodeKind,
            _ module: String,
            _ origin: Origin,
            parent: String?,
        ) -> Node {
            Node(id: id, name: id, kind: kind, module: module, origin: origin, parentID: parent)
        }
        func edge(
            _ source: String,
            _ target: String,
            _ kind: EdgeKind,
            via: String? = nil,
        ) -> Edge {
            Edge(
                id: "\(source)->\(target):\(kind.rawValue)",
                source: source,
                target: target,
                kind: kind,
                viaMemberID: via,
            )
        }
        let nodes = [
            node("module:App", .module, "App", .firstParty, parent: nil),
            node("module:AppTests", .module, "AppTests", .test, parent: nil),
            node("module:Ext", .module, "Ext", .external, parent: nil),
            node("Alpha", .class, "App", .firstParty, parent: "module:App"),
            node("Beta", .struct, "App", .firstParty, parent: "module:App"),
            node("Gamma", .enum, "App", .firstParty, parent: "module:App"),
            node("Proto", .protocol, "App", .firstParty, parent: "module:App"),
            node("field", .property, "App", .firstParty, parent: "Alpha"),
            node("ExtType", .class, "Ext", .external, parent: "module:Ext"),
            node("Tester", .struct, "AppTests", .test, parent: "module:AppTests"),
        ]
        let edges = [
            edge("Alpha", "Proto", .conformance),
            edge("Alpha", "Beta", .propertyType, via: "field"),
            edge("Alpha", "field", .member),
            edge("Alpha", "ExtType", .propertyType),
            edge("Tester", "Alpha", .construction),
            edge("Gamma", "Proto", .conformance),
            edge("Alpha", "Beta", .reference),
            edge("Beta", "Gamma", .paramOrReturnType),
        ]
        return CodeGraph(
            generatedAt: Date(timeIntervalSince1970: 0),
            repoPath: "/test/repo",
            modules: [],
            nodes: nodes,
            edges: edges,
        )
    }

    /// A persistence backed by a throwaway, uniquely-named suite so each test
    /// starts from empty defaults and never touches the app container.
    private func isolatedDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "codegraph.test.\(UUID())"))
    }

    private func makeModel() throws -> GraphViewModel {
        let persistence = try ViewerPersistence(defaults: isolatedDefaults())
        return GraphViewModel(graph: makeGraph(), persistence: persistence)
    }

    private func visibleIDs(_ model: GraphViewModel) -> Set<String> {
        Set(model.visibleNodes.map(\.id))
    }

    private func hasEdge(
        _ model: GraphViewModel,
        from source: String,
        to target: String,
        kind: EdgeKind,
    ) -> Bool {
        model.visibleEdges
            .contains { $0.source == source && $0.target == target && $0.kind == kind }
    }

    // MARK: - Default filters

    @Test func defaultsShowFirstPartyAndTestTypesOnly() throws {
        let model = try makeModel()
        // Members (collapsed), external nodes, and module groupings are hidden by
        // default; the structural + propertyType edges among visible types show.
        #expect(visibleIDs(model) == ["Alpha", "Beta", "Gamma", "Proto", "Tester"])
        #expect(model.visibleEdges.count == 4)
        #expect(hasEdge(model, from: "Alpha", to: "Proto", kind: .conformance))
        #expect(hasEdge(model, from: "Tester", to: "Alpha", kind: .construction))
        // The opt-in `.reference` and `.paramOrReturnType` edges are not default.
        #expect(!hasEdge(model, from: "Alpha", to: "Beta", kind: .reference))
    }

    // MARK: - Origin filters

    @Test func showExternalRevealsExternalNodesAndEdges() throws {
        let model = try makeModel()
        model.showExternal = true
        #expect(visibleIDs(model).contains("ExtType"))
        #expect(hasEdge(model, from: "Alpha", to: "ExtType", kind: .propertyType))
    }

    @Test func hidingTestsRemovesTestNodes() throws {
        let model = try makeModel()
        model.showTests = false
        #expect(visibleIDs(model) == ["Alpha", "Beta", "Gamma", "Proto"])
        #expect(!hasEdge(model, from: "Tester", to: "Alpha", kind: .construction))
    }

    @Test func showModulesRevealsOnlyOriginVisibleModules() throws {
        let model = try makeModel()
        model.showModules = true
        let ids = visibleIDs(model)
        #expect(ids.contains("module:App"))
        #expect(ids.contains("module:AppTests"))
        // The external module stays hidden because showExternal is still off.
        #expect(!ids.contains("module:Ext"))
    }

    // MARK: - Kind / module / name filters

    @Test func nodeKindFilterHidesProtocols() throws {
        let model = try makeModel()
        model.toggleNodeKind(.protocol)
        #expect(!visibleIDs(model).contains("Proto"))
        #expect(!hasEdge(model, from: "Alpha", to: "Proto", kind: .conformance))
    }

    @Test func hidingAModuleHidesItsNodes() throws {
        let model = try makeModel()
        model.toggleModuleHidden("App")
        #expect(visibleIDs(model) == ["Tester"])
    }

    @Test func nameQueryMatchesCaseInsensitively() throws {
        let model = try makeModel()
        model.nameQuery = "Alpha"
        #expect(visibleIDs(model) == ["Alpha"])
        model.nameQuery = "pro"
        #expect(visibleIDs(model) == ["Proto"])
    }

    @Test func edgeKindFilterHidesUnselectedKinds() throws {
        let model = try makeModel()
        model.toggleEdgeKind(.propertyType)
        #expect(!hasEdge(model, from: "Alpha", to: "Beta", kind: .propertyType))
        // Nodes are unaffected by an edge-kind toggle.
        #expect(visibleIDs(model).contains("Beta"))
    }

    // MARK: - Expansion

    @Test func expandingATypeRevealsItsMembers() throws {
        let model = try makeModel()
        #expect(!visibleIDs(model).contains("field"))
        #expect(model.memberCount("Alpha") == 1)
        model.toggleExpanded("Alpha")
        #expect(visibleIDs(model).contains("field"))
        #expect(hasEdge(model, from: "Alpha", to: "field", kind: .member))
        model.toggleExpanded("Alpha")
        #expect(!visibleIDs(model).contains("field"))
    }

    // MARK: - Focus

    @Test func focusLimitsToNeighborhoodAndDepthExpands() throws {
        let model = try makeModel()
        model.focus(on: "Alpha")
        // Depth 1: Alpha and its direct neighbors over included edges. Gamma is two
        // hops away (Gamma → Proto ← Alpha), so it is excluded.
        #expect(visibleIDs(model) == ["Alpha", "Proto", "Beta", "Tester"])
        model.focusDepth = 2
        #expect(visibleIDs(model).contains("Gamma"))
        model.clearFocus()
        #expect(visibleIDs(model) == ["Alpha", "Beta", "Gamma", "Proto", "Tester"])
    }

    // MARK: - Persistence reconciliation

    @Test func reconcileDropsReferencesToVanishedSymbols() throws {
        let graph = makeGraph()
        let persistence = try ViewerPersistence(defaults: isolatedDefaults())
        var state = ViewerState()
        state.pins = ["Alpha": CGPoint(x: 10, y: 20), "Ghost": CGPoint(x: 1, y: 1)]
        state.expanded = ["Alpha", "Ghost2"]
        state.focusRoot = "Ghost3"
        persistence.save(ViewerRecord(current: state), repoPath: graph.repoPath)

        let model = GraphViewModel(graph: graph, persistence: persistence)
        #expect(model.pinned == ["Alpha": CGPoint(x: 10, y: 20)])
        #expect(model.isPinned("Alpha"))
        #expect(!model.isPinned("Ghost"))
        #expect(model.expanded == ["Alpha"])
        // A focus root that no longer exists is cleared, not left blanking the graph.
        #expect(model.focusRoot == nil)
    }

    @Test func reconcileKeepsValidPersistedState() throws {
        let graph = makeGraph()
        let persistence = try ViewerPersistence(defaults: isolatedDefaults())
        var state = ViewerState()
        state.focusRoot = "Beta"
        state.showExternal = true
        persistence.save(ViewerRecord(current: state), repoPath: graph.repoPath)

        let model = GraphViewModel(graph: graph, persistence: persistence)
        #expect(model.focusRoot == "Beta")
        #expect(model.showExternal)
    }
}
