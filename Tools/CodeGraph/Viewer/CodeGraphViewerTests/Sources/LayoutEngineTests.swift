@testable import CodeGraphViewer
import CoreGraphics
import Foundation
import Testing

/// The force-directed layout is seeded from a fixed PRNG and runs no
/// concurrency internally, so the same input must always settle the same way.
struct LayoutEngineTests {
    private func node(_ id: String, module: String = "M") -> LayoutInput.Node {
        .init(id: id, module: module)
    }

    private func edge(_ source: String, _ target: String, weight: Double = 1) -> LayoutInput.Edge {
        .init(source: source, target: target, weight: weight)
    }

    private func sampleInput(
        pinned: [String: CGPoint] = [:],
        initial: [String: CGPoint] = [:],
    ) -> LayoutInput {
        LayoutInput(
            nodes: [
                node("a", module: "X"),
                node("b", module: "X"),
                node("c", module: "X"),
                node("d", module: "Y"),
                node("e", module: "Y"),
                node("f", module: "Y"),
            ],
            edges: [
                edge("a", "b"),
                edge("b", "c"),
                edge("c", "a"),
                edge("d", "e"),
                edge("e", "f"),
                edge("a", "d", weight: 2),
            ],
            pinned: pinned,
            initial: initial,
            size: CGSize(width: 1000, height: 800),
        )
    }

    @Test func sameInputSettlesIdentically() async {
        let engine = LayoutEngine()
        let input = sampleInput()
        let first = await engine.layout(input)
        let second = await engine.layout(input)
        #expect(first == second)
        #expect(first.count == 6)
    }

    @Test func largeBoxesDoNotOverlap() async throws {
        let engine = LayoutEngine()
        // Tall member-row chips must not sit on top of each other: repulsion
        // measures the gap between box borders, not just center distance.
        let box = CGSize(width: 240, height: 160)
        let input = LayoutInput(
            nodes: [
                .init(id: "a", module: "M", size: box),
                .init(id: "b", module: "M", size: box),
                .init(id: "c", module: "M", size: box),
            ],
            edges: [],
            pinned: [:],
            initial: [:],
            size: CGSize(width: 1200, height: 1000),
        )
        let result = await engine.layout(input)
        let ids = ["a", "b", "c"]
        for i in 0 ..< ids.count {
            for j in (i + 1) ..< ids.count {
                let p = try #require(result[ids[i]])
                let q = try #require(result[ids[j]])
                // Rectangles overlap only if they penetrate on *both* axes.
                let penetrateX = box.width - abs(p.x - q.x)
                let penetrateY = box.height - abs(p.y - q.y)
                #expect(penetrateX <= 0 || penetrateY <= 0, "boxes \(ids[i]) and \(ids[j]) overlap")
            }
        }
    }

    @Test func emptyInputProducesEmptyLayout() async {
        let engine = LayoutEngine()
        let input = LayoutInput(
            nodes: [],
            edges: [],
            pinned: [:],
            initial: [:],
            size: CGSize(width: 800, height: 600),
        )
        let result = await engine.layout(input)
        #expect(result.isEmpty)
    }

    @Test func pinnedNodesStayExactlyWhereDropped() async {
        let engine = LayoutEngine()
        let pin = CGPoint(x: 123, y: 456)
        let result = await engine.layout(sampleInput(pinned: ["a": pin]))
        #expect(result["a"] == pin)
    }

    @Test func warmStartPreservesSeededPositions() async {
        let engine = LayoutEngine()
        let seededA = CGPoint(x: 500, y: 500)
        let seededB = CGPoint(x: 820, y: 300)
        // iterations: 0 isolates the seeding/overlay step from the simulation, so
        // the assertions don't depend on the relaxation moving anything.
        let result = await engine.layout(
            sampleInput(initial: ["a": seededA, "b": seededB]),
            iterations: 0,
        )
        #expect(result["a"] == seededA)
        #expect(result["b"] == seededB)
    }

    @Test func newNodesAreSeededNearTheirPlacedNeighbors() async throws {
        let engine = LayoutEngine()
        // `a` is already placed; `b` is brand new and shares an edge with `a`, so
        // a warm start should drop it right next to `a` (within the jitter), not
        // out on the cold seed spiral.
        let placed = CGPoint(x: 640, y: 410)
        let input = LayoutInput(
            nodes: [node("a"), node("b")],
            edges: [edge("a", "b")],
            pinned: [:],
            initial: ["a": placed],
            size: CGSize(width: 1000, height: 800),
        )
        let result = await engine.layout(input, iterations: 0)
        let b = try #require(result["b"])
        let distance = hypot(b.x - placed.x, b.y - placed.y)
        #expect(distance < 30, "new node landed \(distance)pt from its neighbor")
    }

    @Test func cancelledLayoutBailsWithEmptyResult() async {
        let engine = LayoutEngine()
        // A cold layout over many nodes runs the full (expensive) simulation; the
        // task is cancelled before it can start, so the loop's cancellation check
        // should short-circuit to an empty result.
        let nodes = (0 ..< 60).map { node("n\($0)") }
        let edges = (0 ..< 59).map { edge("n\($0)", "n\($0 + 1)") }
        let input = LayoutInput(
            nodes: nodes,
            edges: edges,
            pinned: [:],
            initial: [:],
            size: CGSize(width: 1200, height: 900),
        )
        let task = Task { await engine.layout(input) }
        task.cancel()
        let result = await task.value
        #expect(result.isEmpty)
    }
}
