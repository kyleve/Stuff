import Foundation
import PortholeCore
@_spi(Testing) import PortholeKit
import Testing

@MainActor
struct PortholeSessionRouterTests {
    /// Wires a `Porthole` (with the echo fixture registered) to an in-process
    /// client over a loopback pair.
    private func makeSession() -> (Porthole, TestSessionClient) {
        let porthole = Porthole(configuration: PortholeConfiguration(
            appName: "TestApp",
            bundleID: "com.stuff.test",
        ))
        porthole.register(TestEchoConnector())
        let (deviceTransport, clientTransport) = LoopbackTransport.makePair()
        porthole.attach(transport: deviceTransport)
        let client = TestSessionClient(transport: clientTransport)
        return (porthole, client)
    }

    @Test func helloReturnsAppAndDeviceInfo() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.hello(HelloRequest(clientName: "test")))
        guard case let .helloReply(reply) = response else {
            Issue.record("Expected helloReply, got \(response)")
            return
        }
        #expect(reply.appName == "TestApp")
        #expect(reply.bundleID == "com.stuff.test")
        #expect(reply.protocolVersion == portholeProtocolVersion)
    }

    @Test func listConnectorsIncludesAppAndRegisteredConnectors() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.listConnectors)
        guard case let .connectors(manifests) = response else {
            Issue.record("Expected connectors, got \(response)")
            return
        }
        let ids = Set(manifests.map(\.connector.id))
        #expect(ids.contains("app"))
        #expect(ids.contains("test"))
    }

    @Test func pingEchoesMessageWithTimestamp() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.invokeAction(
            ref: .init(connector: "app", action: "ping"),
            parameters: ["message": "hi"],
        ))
        guard case let .actionResult(value) = response else {
            Issue.record("Expected actionResult, got \(response)")
            return
        }
        #expect(value["message"]?.stringValue == "hi")
        #expect(value["timestamp"]?.dateValue != nil)
    }

    @Test func appInfoQueryReturnsOneRow() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.query(
            ref: .init(connector: "app", source: "app-info"),
            query: PortholeQuery(),
        ))
        guard case let .queryResult(page) = response else {
            Issue.record("Expected queryResult, got \(response)")
            return
        }
        #expect(page.rows.count == 1)
        #expect(page.rows.first?["bundleID"]?.stringValue == "com.stuff.test")
        #expect(page.rows.first?["appName"]?.stringValue == "TestApp")
    }

    @Test func echoActionValidatesAndRuns() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.invokeAction(
            ref: .init(connector: "test", action: "echo"),
            parameters: ["value": 7],
        ))
        guard case let .actionResult(value) = response else {
            Issue.record("Expected actionResult, got \(response)")
            return
        }
        #expect(value["echoed"]?.intValue == 7)
    }

    @Test func missingRequiredParameterFailsValidation() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.invokeAction(
            ref: .init(connector: "test", action: "echo"),
            parameters: .object([:]),
        ))
        guard case let .failure(error) = response, case .invalidParameters = error else {
            Issue.record("Expected invalidParameters, got \(response)")
            return
        }
    }

    @Test func throwingHandlerBecomesHandlerFailed() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.invokeAction(
            ref: .init(connector: "test", action: "boom"),
            parameters: .object([:]),
        ))
        guard case let .failure(error) = response, case .handlerFailed = error else {
            Issue.record("Expected handlerFailed, got \(response)")
            return
        }
    }

    @Test func unknownConnectorAndActionFail() async throws {
        let (_, client) = makeSession()
        await client.start()

        let unknownConnector = try await client.send(.invokeAction(
            ref: .init(connector: "ghost", action: "x"),
            parameters: .object([:]),
        ))
        #expect({ if case .failure(.connectorNotFound) = unknownConnector { true } else { false }
        }())

        let unknownAction = try await client.send(.invokeAction(
            ref: .init(connector: "app", action: "nope"),
            parameters: .object([:]),
        ))
        #expect({ if case .failure(.actionNotFound) = unknownAction { true } else { false } }())
    }

    @Test func numbersQueryReturnsRequestedRows() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.query(
            ref: .init(connector: "test", source: "numbers"),
            query: PortholeQuery(filters: ["count": 3]),
        ))
        guard case let .queryResult(page) = response else {
            Issue.record("Expected queryResult, got \(response)")
            return
        }
        #expect(page.rows.count == 3)
        #expect(page.totalCount == 3)
    }

    @Test func subscribeStreamsEventsAndSessionSurvivesUnsubscribe() async throws {
        let (_, client) = makeSession()
        await client.start()

        let subscribe = try await client.send(.subscribe(ref: .init(
            connector: "test",
            source: "ticks",
        )))
        guard case let .subscribed(subscriptionID) = subscribe else {
            Issue.record("Expected subscribed, got \(subscribe)")
            return
        }

        let events = try await client.nextEvents(3)
        #expect(events.count == 3)
        #expect(events.allSatisfy { $0.0 == subscriptionID })
        #expect(events.first?.1["tick"]?.intValue == 0)

        let unsubscribe = try await client.send(.unsubscribe(subscriptionID: subscriptionID))
        #expect({ if case .pong = unsubscribe { true } else { false } }())

        // The session is still healthy after unsubscribing.
        let ping = try await client.send(.ping)
        #expect({ if case .pong = ping { true } else { false } }())
    }

    @Test func subscribingToANonSubscribableSourceFails() async throws {
        let (_, client) = makeSession()
        await client.start()
        let response = try await client.send(.subscribe(ref: .init(
            connector: "test",
            source: "numbers",
        )))
        guard case let .failure(error) = response, case .subscriptionNotSupported = error else {
            Issue.record("Expected subscriptionNotSupported, got \(response)")
            return
        }
    }

    @Test func activeSessionCountReflectsAttachedSessions() async throws {
        let (porthole, client) = makeSession()
        await client.start()
        _ = try await client.send(.ping)
        #expect(porthole.state.activeSessionCount == 1)
    }
}
