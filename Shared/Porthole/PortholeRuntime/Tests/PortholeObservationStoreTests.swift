import Foundation
@testable import PortholeRuntime
import Testing

struct PortholeObservationStoreTests {
    @Test func retainsOnlyTheLatestSampleAndPreservesItOnFailure() throws {
        var store = PortholeObservationStore()
        let request = PortholeObservationStoreTestSupport.request()
        let generation = UUID()
        let leaseID = UUID()
        try PortholeObservationStoreTestSupport.start(
            request,
            in: &store,
            generation: generation,
            leaseID: leaseID,
        )
        #expect(try store.validateStart(request, owner: nil) == false)
        for count in 1 ... 1000 {
            _ = store.publish(
                .success(.init(
                    invocationID: UUID(),
                    capturedAt: Date(),
                    value: .integer(Int64(count)),
                )),
                for: request.reference,
                generation: generation,
            )
        }
        let snapshot = try #require(try store.snapshotIfReady(
            request.reference,
            afterSequence: nil,
            waitMilliseconds: 0,
        ))
        #expect(snapshot.latestSample?.sequence == 1000)
        #expect(snapshot.latestSample?.value == .integer(1000))
        let result = store.publish(
            .failure(PortholeError.operationFailed("offline")),
            for: request.reference,
            generation: generation,
        )
        #expect(result.shouldContinue == false)
        #expect(result.releasedLeaseID == leaseID)
        let failed = try #require(try store.snapshotIfReady(
            request.reference,
            afterSequence: 1000,
            waitMilliseconds: 10000,
        ))
        guard case let .failed(message, lastSample) = failed.state
        else { Issue.record("Expected a terminal observation failure"); return }
        #expect(message.contains("offline"))
        #expect(lastSample == snapshot.latestSample)
        #expect(try store.stop(request.reference, owner: nil) == nil)
    }

    @Test func stopTombstoneRejectsDelayedStartAndDisableDoesNotForgetIt() throws {
        var store = PortholeObservationStore()
        let request = PortholeObservationStoreTestSupport.request()
        #expect(try store.stop(request.reference, owner: nil) == nil)
        _ = store.disable()
        #expect(throws: PortholeError.observationEnded) { try store.validateStart(
            request,
            owner: nil,
        ) }
        _ = store.invalidate(request.reference.scope)
        try store.validateStart(request, owner: nil)
    }

    @Test func boundsObservationCountAndKeepsExistingStopsAvailable() throws {
        var store = PortholeObservationStore()
        var references: [PortholeObservationReference] = []
        for _ in 0 ..< 32 {
            let request = PortholeObservationStoreTestSupport.request()
            try PortholeObservationStoreTestSupport.start(
                request,
                in: &store,
                generation: UUID(),
                leaseID: UUID(),
            )
            references.append(request.reference)
        }
        let next = PortholeObservationStoreTestSupport.request()
        #expect(throws: PortholeError.self) { try store.validateStart(next, owner: nil) }
        let first = try #require(references.first)
        _ = try store.stop(first, owner: nil)
        try store.validateStart(next, owner: nil)
        _ = store.disable()
    }

    @Test func stopFinishesAnActuallyRegisteredLongPollAndReleasesItsLease() async throws {
        var store = PortholeObservationStore()
        let request = PortholeObservationStoreTestSupport.request()
        let leaseID = UUID()
        try PortholeObservationStoreTestSupport.start(
            request,
            in: &store,
            generation: UUID(),
            leaseID: leaseID,
        )
        await #expect(throws: PortholeError.observationEnded) {
            let _: PortholeObservationSnapshot =
                try await withCheckedThrowingContinuation { continuation in
                    do {
                        try store.wait(
                            for: request.reference,
                            waiterID: UUID(),
                            afterSequence: nil,
                            waitMilliseconds: 10000,
                            continuation: continuation,
                            expired: { _ in },
                        )
                        #expect(try store.stop(request.reference, owner: nil) == leaseID)
                    } catch { continuation.resume(throwing: error) }
                }
        }
    }

    @Test func closedOwnerCannotCreateAnObservationAfterDelayedWorkResumes() throws {
        var store = PortholeObservationStore()
        let owner = PortholeObservationOwnerID(rawValue: UUID())
        _ = store.stop(ownedBy: owner)
        #expect(throws: PortholeError.observationEnded) {
            try store.validateStart(PortholeObservationStoreTestSupport.request(), owner: owner)
        }
        try store.validateStart(
            PortholeObservationStoreTestSupport.request(),
            owner: .init(rawValue: UUID()),
        )
    }
}
