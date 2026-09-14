import Foundation
import PortholeCore
@testable import PortholeRemote
import Testing

@Suite(.timeLimit(.minutes(1))) struct PortholeRemoteRequestReaderTests {
    @Test func eofCancelsDispatchAndEndsOwnershipBeforeNativeCodeReturns() async throws {
        let executor = PortholeRemoteObservationTestExecutor(
            effect: .read,
            sampleCount: 0,
            delaysStart: true,
        )
        let session = PortholeRemoteTestSupport.dispatcher(executor: executor).makeSession()
        let observation = PortholeObservationRequest(
            id: .init(rawValue: UUID()),
            invocation: PortholeRemoteTestSupport.invocation(),
            intervalMilliseconds: 1000,
        )
        let request = try PortholeRemoteRequest(
            requestID: UUID(),
            operation: .invoke(.init(
                id: UUID(),
                scope: observation.invocation.scope,
                capabilityID: PortholeObservationCapabilities.start,
                receiver: nil,
                arguments: .object(["request": .encoding(observation)]),
            )),
        )
        let dispatch = Task { await session.respond(to: request) }
        await executor.waitForStarts(1)
        let source = PortholeRemoteRequestReaderTestSource(frames: [])
        let reader = PortholeRemoteRequestReader(source: source) {
            dispatch.cancel()
            await session.close()
        }
        await source.waitForReads(1)
        source.finish()
        await reader.waitUntilEnded()
        #expect(dispatch.isCancelled)
        #expect(await executor.endedOwners.count == 1)
        #expect(await executor.stops == [observation.reference])
        await executor.releaseStart()
        let response = await dispatch.value
        guard case .failure = response.result
        else { Issue.record("A delayed start survived connection cleanup."); return }
    }

    @Test func overflowClosesBeforeAnyBufferedRequestCanExecute() async throws {
        let executor = PortholeRemoteTestExecutor(effect: .read)
        let session = PortholeRemoteTestSupport.dispatcher(executor: executor).makeSession()
        let request = PortholeRemoteRequest(
            requestID: UUID(),
            operation: .invoke(PortholeRemoteTestSupport.invocation()),
        )
        let frame = try JSONEncoder().encode(request)
        let source = PortholeRemoteRequestReaderTestSource(frames: [frame, frame, frame])
        let cleanup = PortholeRemoteTestCounter()
        let reader = PortholeRemoteRequestReader(source: source) {
            cleanup.increment()
            await session.close()
        }
        await reader.waitUntilEnded()
        #expect(source.readCount == 2)
        #expect(source.hasEnded)
        #expect(cleanup.count == 1)
        var iterator = reader.requests.makeAsyncIterator()
        // AsyncThrowingStream can drain its buffer after finish(error). Session closure is final.
        let next = try await iterator.next()
        let buffered = try #require(next)
        let bufferedRequest = try JSONDecoder().decode(
            PortholeRemoteRequest.self,
            from: buffered,
        )
        let response = await session.respond(to: bufferedRequest)
        guard case .failure = response.result
        else { Issue.record("A buffered request executed after the connection closed."); return }
        #expect(await executor.received.isEmpty)
        await #expect(throws: PortholeRemoteError.connectionBusy) { try await iterator.next() }
    }

    @Test func repeatedCancellationUnblocksReceiveAndCleansUpOnce() async {
        let source = PortholeRemoteRequestReaderTestSource(frames: [])
        let cleanup = PortholeRemoteTestCounter()
        let reader = PortholeRemoteRequestReader(source: source) { cleanup.increment() }
        await source.waitForReads(1)
        reader.cancel()
        reader.cancel()
        reader.cancel()
        await reader.waitUntilEnded()
        #expect(source.hasEnded)
        #expect(source.readCount == 1)
        #expect(cleanup.count == 1)
    }

    @Test func oversizedFrameEndsBeforeItReachesTheDispatcher() async {
        let source = PortholeRemoteRequestReaderTestSource(frames: [
            Data(repeating: 0, count: PortholeRemoteFraming.maximumBytes + 1),
        ])
        let cleanup = PortholeRemoteTestCounter()
        let reader = PortholeRemoteRequestReader(source: source) { cleanup.increment() }
        await reader.waitUntilEnded()
        var iterator = reader.requests.makeAsyncIterator()
        await #expect(throws: PortholeRemoteError.frameTooLarge) { try await iterator.next() }
        #expect(source.readCount == 1)
        #expect(source.hasEnded)
        #expect(cleanup.count == 1)
    }
}
