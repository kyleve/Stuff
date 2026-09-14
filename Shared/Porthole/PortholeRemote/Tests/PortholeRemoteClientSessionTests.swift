import Foundation
import PortholeCore
@testable import PortholeRemote
import Testing

@Suite(.timeLimit(.minutes(1))) struct PortholeRemoteClientSessionTests {
    @Test func oversizedRequestsFailBeforeTheyEnterTheQueue() async throws {
        let transport = PortholeRemoteQueueTestTransport()
        let session = PortholeRemoteClientSession(transport: transport)
        let first = Task { try await session.exchange(Data([1])) }
        await transport.waitForRequest()
        await #expect(throws: PortholeRemoteError.frameTooLarge) {
            try await session.exchange(Data(
                repeating: 0,
                count: PortholeRemoteFraming.maximumBytes + 1,
            ))
        }
        #expect(await transport.requests.count == 1)
        await transport.reply(Data([2]))
        #expect(try await first.value == Data([2]))
        await session.close()
    }

    @Test func queueRejectsOverflowAndCloseReleasesEveryPendingRequest() async throws {
        let transport = PortholeRemoteQueueTestTransport()
        let session = PortholeRemoteClientSession(transport: transport)
        let first = Task { try await session.exchange(Data([1])) }
        await transport.waitForRequest()
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 33 {
                group.addTask {
                    do {
                        _ = try await session.exchange(Data([2]))
                        Issue.record("A queued request reached the held transport")
                        return false
                    } catch PortholeRemoteError.connectionBusy { return true }
                    catch PortholeRemoteError.disconnected { return false }
                    catch { Issue.record(error); return false }
                }
            }
            #expect(await group.next() == true)
            await session.close()
            for await rejectedForCapacity in group {
                #expect(rejectedForCapacity == false)
            }
        }
        await #expect(throws: PortholeRemoteError.disconnected) { try await first.value }
        await #expect(throws: PortholeRemoteError.disconnected) {
            try await session.exchange(Data([3]))
        }
        #expect(await transport.requests == [Data([1])])
    }

    @Test func timeoutWithUnchangedSampleDoesNotDuplicateOrFailTheStream() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 1,
            delaysStart: false,
        )
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        let client = PortholeRemoteClient(transport: transport)
        let stream = client.observations(
            of: PortholeRemoteTestSupport.invocation(),
            interval: .seconds(1),
        )
        await executor.waitForReads(2)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == .integer(1))
        try await executor.releaseReadsWithLastSample()
        await executor.waitForReads(3)
        await client.close()
        await #expect(throws: PortholeRemoteError.disconnected) { try await iterator.next() }
    }

    @Test func slowConsumerReceivesOnlyLatestUnreadSample() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 20,
            delaysStart: false,
        )
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        let client = PortholeRemoteClient(transport: transport)
        let stream = client.observations(
            of: PortholeRemoteTestSupport.invocation(),
            interval: .seconds(1),
        )
        await executor.waitForReads(21)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == .integer(20))
        #expect(await executor.starts.count == 1)
        #expect(await executor.directInvocations == 0)
        await client.close()
        await executor.waitForStops(1)
        await #expect(throws: PortholeRemoteError.disconnected) { try await iterator.next() }
    }

    @Test func consumerCancellationStopsRuntimeObservationAndKeepsConnectionUsable() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 1,
            delaysStart: false,
        )
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        let client = PortholeRemoteClient(transport: transport)
        let stream = client.observations(
            of: PortholeRemoteTestSupport.invocation(),
            interval: .seconds(1),
        )
        let consumer = Task { for try await _ in stream {} }
        await executor.waitForReads(2)
        consumer.cancel()
        try await consumer.value
        try await executor.releaseReads()
        await executor.waitForStops(1)
        #expect(await transport.isClosed == false)
        #expect(try await client.application().name == "Test")
        await client.close()
        #expect(await executor.stops.count == 1)
    }

    @Test func closingClientEndsPendingReadAndRejectsNewRequests() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 0,
            delaysStart: false,
        )
        let transport = PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
            .dispatcher(executor: executor))
        let client = PortholeRemoteClient(transport: transport)
        let stream = client.observations(
            of: PortholeRemoteTestSupport.invocation(),
            interval: .seconds(1),
        )
        await executor.waitForReads(1)
        await client.close()
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: PortholeRemoteError.disconnected) { try await iterator.next() }
        await #expect(throws: PortholeRemoteError.disconnected) { try await client.application() }
        #expect(await executor.stops.count == 1)
        #expect(await transport.isClosed)
    }

    @Test(arguments: [PortholeEffect.unknown, .mutation])
    func runtimeReadRestrictionEndsStreamWithoutDirectInvocation(
        effect: PortholeEffect,
    ) async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: effect,
            sampleCount: 0,
            delaysStart: false,
        )
        let client =
            PortholeRemoteClient(
                transport: PortholeRemoteTestTransport(dispatcher: PortholeRemoteTestSupport
                    .dispatcher(executor: executor)),
            )
        let stream = client.observations(
            of: PortholeRemoteTestSupport.invocation(),
            interval: .seconds(1),
        )
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: (any Error).self) { try await iterator.next() }
        #expect(await executor.starts.count == 1)
        #expect(await executor.reads == 0)
        #expect(await executor.directInvocations == 0)
        #expect(await executor.stops.count == 1)
        await client.close()
    }
}
