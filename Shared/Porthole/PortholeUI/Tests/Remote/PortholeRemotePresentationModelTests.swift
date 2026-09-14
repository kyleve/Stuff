import Foundation
import PortholeCore
import PortholeRemote
@testable import PortholeUI
import Testing

@MainActor
struct PortholeRemotePresentationModelTests {
    @Test func evidenceNavigationCannotRebindToAReplacementConnection() async throws {
        let server = try PortholeRemoteUITestSupport.server()
        let connector = PortholeRemoteUIConnector(
            transport: PortholeRemoteUITransport(),
            servers: [server],
        )
        let model = PortholeRemotePresentationModel(connector: connector, clientName: "Test")
        await model.connect(server: server)
        let saved = try #require(model.evidenceNavigation)
        #expect(try await saved.reader.capabilities(in: PortholeRemoteUITestSupport.scope)
            .count == 1)
        await model.disconnect()
        await model.connect(server: server)
        await #expect(throws: PortholeRemoteError.self) {
            try await saved.reader.capabilities(in: PortholeRemoteUITestSupport.scope)
        }
        await #expect(throws: PortholeRemoteError.self) {
            try await saved.execute(.init(
                id: UUID(),
                scope: PortholeRemoteUITestSupport.scope,
                capabilityID: PortholeRemoteUITestSupport.capability().id,
                receiver: nil,
                arguments: .object(["value": .string("changed")]),
            ))
        }
        await model.disconnect()
    }

    @Test func disconnectRejectsLateConnectionAndClosesItsTransport() async throws {
        let server = try PortholeRemoteUITestSupport.server()
        let transport = PortholeRemoteUITransport()
        let connector = PortholeRemoteUIConnector(transport: transport, servers: [server])
        await connector.hold()
        let model = PortholeRemotePresentationModel(connector: connector, clientName: "Test")
        let connection = Task { await model.connect(server: server) }
        await connector.waitForArrival()
        await model.disconnect()
        await connector.release()
        await connection.value
        guard case .idle = model.connection
        else { Issue.record("A dismissed connection published late state"); return }
        #expect(await transport.closed)
    }

    @Test func loadsSavedServersAndCapabilitiesThroughInjectedServices() async throws {
        let server = try PortholeRemoteUITestSupport.server()
        let connector = PortholeRemoteUIConnector(
            transport: PortholeRemoteUITransport(),
            servers: [server],
        )
        let model = PortholeRemotePresentationModel(connector: connector, clientName: "Test")
        await model.loadServers()
        #expect(model.servers == [server])
        await model.connect(server: server)
        await model.select(scope: PortholeRemoteUITestSupport.scope)
        guard case let .loaded(scope, snapshot) = model.scopeState
        else { Issue.record("Expected a loaded scope"); return }
        #expect(scope == PortholeRemoteUITestSupport.scope)
        #expect(snapshot.capabilities == [PortholeRemoteUITestSupport.capability()])
        #expect(snapshot.objects == nil)
        #expect(snapshot.contexts == nil)
        await model.disconnect()
    }
}
