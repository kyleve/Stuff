import Foundation
import PortholeCore
@testable import PortholeRemote
import Testing

@Suite(.timeLimit(.minutes(1))) struct PortholeRemoteSessionTests {
    @Test func nativeRuntimeOwnsTheObservationLedgerAcrossScopeTurnover() async throws {
        let executor = PortholeRemoteLedgerTestExecutor()
        let session = PortholeRemoteTestSupport.dispatcher(executor: executor).makeSession()
        for _ in 0 ..< 4097 {
            let reference = PortholeObservationReference(
                id: .init(rawValue: UUID()),
                scope: .init(id: PortholeRemoteTestSupport.scope.id, generation: UUID()),
            )
            let response = try await session.respond(to: .init(
                requestID: UUID(),
                operation: .invoke(.init(
                    id: UUID(),
                    scope: reference.scope,
                    capabilityID: PortholeObservationCapabilities.stop,
                    receiver: nil,
                    arguments: .object(["observation": .encoding(reference)]),
                )),
            ))
            guard case .value(.null) = response.result
            else { Issue.record("Stop did not reach the native executor"); return }
        }
        let request = PortholeObservationRequest(
            id: .init(rawValue: UUID()),
            invocation: PortholeRemoteTestSupport.invocation(),
            intervalMilliseconds: 1000,
        )
        let response = try await session.respond(to: .init(
            requestID: UUID(),
            operation: .invoke(.init(
                id: UUID(),
                scope: request.invocation.scope,
                capabilityID: PortholeObservationCapabilities.start,
                receiver: nil,
                arguments: .object(["request": .encoding(request)]),
            )),
        ))
        guard case let .value(value) = response.result
        else { Issue.record("A new start was rejected by obsolete session bookkeeping"); return
        }
        #expect(try value.decode(PortholeObservationReference.self) == request.reference)
        await session.close()
    }

    @Test func nestedAdapterCallsInheritNativeOwnershipAndEndOnDisconnect() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 1,
            delaysStart: false,
        )
        let client = PortholeRemoteClient(transport: PortholeRemoteTestTransport(
            dispatcher: PortholeRemoteTestSupport.dispatcher(executor: executor),
        ))
        let result = try await client.invoke(.init(
            id: UUID(),
            scope: PortholeRemoteTestSupport.scope,
            capabilityID: .init(rawValue: "test.nested-start"),
            receiver: nil,
            arguments: .object([:]),
        ))
        let reference = try result.decode(PortholeObservationReference.self)
        let owners = await executor.owners
        #expect(owners.count == 2)
        #expect(Set(owners).count == 1)
        let owner = try #require(owners.first)
        let snapshot = try await client.readObservation(
            reference,
            afterSequence: nil,
            waitMilliseconds: 0,
        )
        #expect(snapshot.latestSample?.value == .integer(1))
        await client.close()
        #expect(await executor.endedOwners == [owner])
        #expect(await executor.stops == [reference])
    }

    @Test func replayedStartCannotAdoptAnotherConnectionsObservation() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 0,
            delaysStart: false,
        )
        let dispatcher = PortholeRemoteTestSupport.dispatcher(executor: executor)
        let owner =
            PortholeRemoteClient(transport: PortholeRemoteTestTransport(dispatcher: dispatcher))
        let other =
            PortholeRemoteClient(transport: PortholeRemoteTestTransport(dispatcher: dispatcher))
        let request = PortholeObservationRequest(
            id: .init(rawValue: UUID()),
            invocation: PortholeRemoteTestSupport.invocation(),
            intervalMilliseconds: 1000,
        )
        let reference = try await owner.startObservation(request)
        await #expect(throws: (any Error).self) { try await other.startObservation(request) }
        await other.close()
        #expect(await executor.stops.isEmpty)
        await owner.close()
        #expect(await executor.stops == [reference])
    }

    @Test func observationsStayBoundToTheirAuthenticatedConnection() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 0,
            delaysStart: false,
        )
        let dispatcher = PortholeRemoteTestSupport.dispatcher(executor: executor)
        let owner =
            PortholeRemoteClient(transport: PortholeRemoteTestTransport(dispatcher: dispatcher))
        let other =
            PortholeRemoteClient(transport: PortholeRemoteTestTransport(dispatcher: dispatcher))
        let reference = try await owner.startObservation(.init(
            id: .init(rawValue: UUID()),
            invocation: PortholeRemoteTestSupport.invocation(),
            intervalMilliseconds: 1000,
        ))
        await #expect(throws: (any Error).self) {
            try await other.readObservation(reference, afterSequence: nil, waitMilliseconds: 0)
        }
        await #expect(throws: (any Error).self) { try await other.stopObservation(reference) }
        await #expect(throws: (any Error).self) {
            try await owner.invoke(.init(
                id: UUID(),
                scope: .init(id: reference.scope.id, generation: UUID()),
                capabilityID: PortholeObservationCapabilities.read,
                receiver: nil,
                arguments: .object([
                    "observation": .encoding(reference),
                    "afterSequence": .null,
                    "waitMilliseconds": .integer(0),
                ]),
            ))
        }
        #expect(await executor.reads == 0)
        #expect(await executor.stops.isEmpty)
        await other.close()
        #expect(await executor.stops.isEmpty)
        await owner.close()
        #expect(await executor.stops == [reference])
    }

    @Test func closeStopsStartBeforeItsDelayedReply() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 0,
            delaysStart: true,
        )
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        let client = PortholeRemoteClient(transport: transport)
        let request = PortholeObservationRequest(
            id: .init(rawValue: UUID()),
            invocation: PortholeRemoteTestSupport.invocation(),
            intervalMilliseconds: 1000,
        )
        let start = Task { try await client.startObservation(request) }
        await executor.waitForStarts(1)
        await client.close()
        #expect(await executor.stops == [.init(id: request.id, scope: request.invocation.scope)])
        await executor.releaseStart()
        await #expect(throws: PortholeRemoteError.disconnected) { try await start.value }
    }

    @Test func lostStartReplyStopsObservationWithoutRetryingStart() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 0,
            delaysStart: false,
        )
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        await transport.loseReplies()
        let client = PortholeRemoteClient(transport: transport)
        let request = PortholeObservationRequest(
            id: .init(rawValue: UUID()),
            invocation: PortholeRemoteTestSupport.invocation(),
            intervalMilliseconds: 1000,
        )
        await #expect(throws: PortholeRemoteError.disconnected) {
            try await client.startObservation(request)
        }
        #expect(await executor.starts.count == 1)
        #expect(await executor.stops == [.init(id: request.id, scope: request.invocation.scope)])
        #expect(await transport.requests == 1)
        await client.close()
    }
}
