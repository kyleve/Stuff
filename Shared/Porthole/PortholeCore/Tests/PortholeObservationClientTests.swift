import Foundation
import PortholeCore
import Testing

struct PortholeObservationClientTests {
    @Test func startUsesTheKnownObservationIdentityAndTheOrdinaryExecutor() async throws {
        let request = PortholeObservationTestSupport.request()
        let executor =
            try PortholeObservationRecordingExecutor(result: .encoding(request.reference))
        #expect(try await executor.startObservation(request) == request.reference)
        let invocation = try #require(await executor.invocations.first)
        #expect(invocation.id == request.id.rawValue)
        #expect(invocation.scope == request.invocation.scope)
        #expect(invocation.capabilityID == PortholeObservationCapabilities.start)
        #expect(try invocation.arguments["request"]?
            .decode(PortholeObservationRequest.self) == request)
    }

    @Test func readForwardsItsCursorAndRejectsEvidenceFromAnotherObservation() async throws {
        let request = PortholeObservationTestSupport.request()
        let snapshot = PortholeObservationSnapshot(observation: request.reference, state: .waiting)
        let executor = try PortholeObservationRecordingExecutor(result: .encoding(snapshot))
        #expect(try await executor.readObservation(
            request.reference,
            afterSequence: 3,
            waitMilliseconds: 10000,
        ) == snapshot)
        let invocation = try #require(await executor.invocations.first)
        #expect(invocation.id != request.id.rawValue)
        #expect(invocation.capabilityID == PortholeObservationCapabilities.read)
        #expect(invocation.arguments["afterSequence"] == .integer(3))
        #expect(invocation.arguments["waitMilliseconds"] == .integer(10000))
        let other = PortholeObservationTestSupport.request()
        await #expect(throws: PortholeError.operationConflict) {
            try await executor.readObservation(
                other.reference,
                afterSequence: nil,
                waitMilliseconds: 0,
            )
        }
    }

    @Test func stopUsesTheKnownReferenceWithoutRequiringAStartReply() async throws {
        let request = PortholeObservationTestSupport.request()
        let executor = PortholeObservationRecordingExecutor(result: .null)
        let client = PortholeObservationClient { invocation in await executor.invoke(invocation) }
        try await client.stopObservation(request.reference)
        try await client.stopObservation(request.reference)
        let invocations = await executor.invocations
        #expect(invocations.count == 2)
        #expect(Set(invocations.map(\.id)).count == 2)
        #expect(invocations.allSatisfy { $0.capabilityID == PortholeObservationCapabilities.stop })
        #expect(try invocations.first?.arguments["observation"]?
            .decode(PortholeObservationReference.self) == request.reference)
    }

    @Test func mismatchedStartReplyIsRejected() async throws {
        let request = PortholeObservationTestSupport.request()
        let executor =
            try PortholeObservationRecordingExecutor(
                result: .encoding(PortholeObservationTestSupport
                    .request().reference),
            )
        await #expect(throws: PortholeError.operationConflict) {
            try await executor.startObservation(request)
        }
    }
}
