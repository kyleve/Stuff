import Foundation
import PortholeCore
@testable import PortholeMCP
import Testing

struct PortholeMCPDispatcherTests {
    private func dispatcher(_ session: FakeSession) -> PortholeMCPDispatcher {
        PortholeMCPDispatcher(session: session, manifests: session.manifests)
    }

    @Test func overviewReturnsManifestJSON() async {
        let result = await dispatcher(FakeSession(manifests: fixtureManifests()))
            .call(name: "porthole_overview", arguments: .object([:]))
        guard case let .json(value) = result else {
            Issue.record("Expected json, got \(result)")
            return
        }
        #expect(value.arrayValue?.first?["id"]?.stringValue == "test")
    }

    @Test func actionInvokeReturnsResult() async {
        var session = FakeSession(manifests: fixtureManifests())
        session.onInvoke = { ref, params in
            #expect(ref.action.rawValue == "echo")
            return .object(["echoed": params["value"] ?? .null])
        }
        let result = await dispatcher(session).call(name: "act_test_echo", arguments: ["value": 5])
        guard case let .json(value) = result else {
            Issue.record("Expected json, got \(result)")
            return
        }
        #expect(value["echoed"]?.intValue == 5)
    }

    @Test func pngResultBecomesImage() async {
        var session = FakeSession(manifests: fixtureManifests())
        session.onInvoke = { _, _ in .object(["image": .data(pngData())]) }
        let result = await dispatcher(session).call(name: "act_test_echo", arguments: ["value": 1])
        guard case let .image(data) = result else {
            Issue.record("Expected image, got \(result)")
            return
        }
        #expect(data == pngData())
    }

    @Test func querySplitsLimitAndCursorFromFilters() async {
        var session = FakeSession(manifests: fixtureManifests())
        session.onQuery = { _, query in
            #expect(query.limit == 10)
            #expect(query.cursor == "c1")
            #expect(query.filters["count"]?.intValue == 3)
            #expect(query.filters["limit"] == nil)
            return PortholePage(rows: [["n": 0]], nextCursor: "c2", totalCount: 99)
        }
        let result = await dispatcher(session).call(
            name: "query_test_rows",
            arguments: ["count": 3, "limit": 10, "cursor": "c1"],
        )
        guard case let .json(value) = result else {
            Issue.record("Expected json, got \(result)")
            return
        }
        #expect(value["rows"]?.arrayValue?.count == 1)
        #expect(value["nextCursor"]?.stringValue == "c2")
        #expect(value["totalCount"]?.intValue == 99)
    }

    @Test func tailCollectsBoundedEvents() async {
        var session = FakeSession(manifests: fixtureManifests())
        session.onSubscribe = { _ in
            AsyncThrowingStream { continuation in
                for tick in 0 ..< 3 {
                    continuation.yield(.object(["tick": .int(Int64(tick))]))
                }
                continuation.finish()
            }
        }
        let result = await dispatcher(session).call(
            name: "tail_test_ticks",
            arguments: ["durationSeconds": 2, "maxEvents": 100],
        )
        guard case let .json(value) = result else {
            Issue.record("Expected json, got \(result)")
            return
        }
        #expect(value.arrayValue?.count == 3)
    }

    @Test func unknownToolFails() async {
        let result = await dispatcher(FakeSession(manifests: fixtureManifests()))
            .call(name: "act_ghost_nope", arguments: .object([:]))
        guard case .failure = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
    }

    @Test func handlerErrorBecomesFailure() async {
        var session = FakeSession(manifests: fixtureManifests())
        session.onInvoke = { _, _ in throw PortholeError.handlerFailed("boom") }
        let result = await dispatcher(session).call(name: "act_test_echo", arguments: ["value": 1])
        guard case .failure = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
    }
}
