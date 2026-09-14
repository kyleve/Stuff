import Foundation
import PortholeCore
@testable import PortholeRemote
import Testing

struct PortholeRemoteClientTests {
    @Test func aggregatesCatalogAcrossBoundedPages() async throws {
        let executor = PortholeRemoteTestExecutor(effect: .read)
        let catalog = (0 ..< 405).map { index in
            PortholeCapability(
                id: .init(rawValue: "test.\(index)"),
                module: .init(rawValue: "Test"),
                name: "Operation \(index)",
                summary: "",
                parameters: [],
                result: .string,
                effect: .read,
                source: nil,
                ownership: .adapter,
                availability: .callable,
            )
        }
        await executor.setCatalog(catalog)
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        let client = PortholeRemoteClient(transport: transport)
        #expect(try await client.capabilities(in: PortholeRemoteTestSupport.scope) == catalog)
        #expect(await transport.requests == 3)
    }

    @Test func rejectsMismatchedResponseIdentity() async throws {
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: PortholeRemoteTestExecutor(effect: .read)))
        await transport.corruptResponses()
        let client = PortholeRemoteClient(transport: transport)
        await #expect(throws: PortholeRemoteError.invalidMessage) { try await client.application() }
    }

    @Test func uncertainTransportFailureNeverRetriesAnInvocation() async throws {
        let executor = PortholeRemoteTestExecutor(effect: .read)
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        await transport.loseReplies()
        let client = PortholeRemoteClient(transport: transport)
        await #expect(throws: PortholeRemoteError.disconnected) {
            try await client.invoke(PortholeRemoteTestSupport.invocation())
        }
        #expect(await transport.requests == 1)
        #expect(await executor.received.count == 1)
    }

    @Test func preservesApprovalProposal() async throws {
        let executor = PortholeRemoteTestExecutor(effect: .mutation)
        let client =
            PortholeRemoteClient(
                transport: PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
                    .dispatcher(executor: executor)),
            )
        let invocation = PortholeRemoteTestSupport.invocation()
        await #expect(throws: PortholeError.approvalRequired(.init(
            invocation: invocation,
            capability: PortholeRemoteTestSupport.capability(effect: .mutation),
        ))) {
            try await client.invoke(invocation)
        }
        #expect(await executor.received.count == 1)
    }
}
