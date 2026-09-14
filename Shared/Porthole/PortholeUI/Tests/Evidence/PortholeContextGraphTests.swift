import Foundation
import PortholeCore
@testable import PortholeUI
import Testing

struct PortholeContextGraphTests {
    @Test func resolvesDirectedNeighborsOnlyWithinTheOriginalGeneration() {
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let link = PortholeContextLink(
            id: .init(rawValue: "child"),
            label: "Recorded flight decision",
            relation: "explains",
        )
        let focus = context("focus", scope: scope, links: [link])
        let parent = context(
            "parent",
            scope: scope,
            links: [.init(id: focus.id, label: "Issue", relation: "opened")],
        )
        let child = context("child", scope: scope, links: [])
        let foreign = context(
            "foreign",
            scope: .init(id: scope.id, generation: UUID()),
            links: [.init(id: focus.id, label: "Other issue", relation: "opened")],
        )
        let graph = PortholeContextGraph(context: focus, knownContexts: [parent, child, foreign])
        #expect(graph.incoming.map(\.reference) == [.context(parent)])
        #expect(graph.outgoing.map(\.reference) == [.context(child)])
        #expect(graph.outgoing.map(\.relation) == ["explains"])
        let unresolved = PortholeContextGraph(context: focus, knownContexts: [])
        #expect(unresolved.outgoing.map(\.reference) == [.contextLink(link, scope: scope)])
    }

    private func context(
        _ name: String,
        scope: PortholeScopeToken,
        links: [PortholeContextLink],
    ) -> PortholeContext {
        PortholeContext(
            id: .init(rawValue: name),
            title: name,
            scope: scope,
            capturedAt: Date(timeIntervalSince1970: 0),
            values: .null,
            objects: [],
            links: links,
            source: nil,
        )
    }
}
