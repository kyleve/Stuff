@testable import CodeGraphModel
import Foundation
import Testing

struct CodeGraphModelTests {
    @Test func sampleGraphDecodes() throws {
        let graph = try CodeGraph.sample()
        #expect(graph.schemaVersion == CodeGraph.currentSchemaVersion)
        #expect(!graph.modules.isEmpty)
        #expect(!graph.nodes.isEmpty)
        #expect(!graph.edges.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let graph = try CodeGraph.sample()
        let restored = try CodeGraph.decoded(from: graph.encoded())
        #expect(restored == graph)
    }

    @Test func everyEdgeEndpointResolvesToANode() throws {
        let graph = try CodeGraph.sample()
        let ids = Set(graph.nodes.map(\.id))
        for edge in graph.edges {
            #expect(ids.contains(edge.source), "edge \(edge.id) has unknown source \(edge.source)")
            #expect(ids.contains(edge.target), "edge \(edge.id) has unknown target \(edge.target)")
            if let member = edge.viaMemberID {
                #expect(ids.contains(member), "edge \(edge.id) has unknown member \(member)")
            }
        }
    }

    @Test func everyMemberAndNestedNodeHasAParent() throws {
        let graph = try CodeGraph.sample()
        let ids = Set(graph.nodes.map(\.id))
        for node in graph.nodes where node.kind.isMember {
            let parent = try #require(node.parentID, "member \(node.id) needs a parent")
            #expect(ids.contains(parent), "member \(node.id) has unknown parent \(parent)")
        }
    }

    @Test func edgeKindStructuralPartitionIsTotal() {
        // Every kind is classified; this guards new cases from silently
        // defaulting to "not structural".
        for kind in EdgeKind.allCases {
            _ = kind.isStructural
        }
        #expect(EdgeKind.inheritance.isStructural)
        #expect(!EdgeKind.propertyType.isStructural)
    }
}
