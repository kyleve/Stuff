import Foundation
import PortholeCore
import Testing

struct PortholeObservationTests {
    @Test func requestsAndLatestEvidenceRoundTripWithoutLosingIntegerPrecision() throws {
        let request = PortholeObservationTestSupport.request()
        #expect(try PortholeValue.encoding(request)
            .decode(PortholeObservationRequest.self) == request)
        let sample = PortholeObservationSample(
            sequence: 5,
            invocationID: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1000),
            value: .unsignedInteger(UInt64.max),
        )
        for state in [
            PortholeObservationSnapshot.State.waiting,
            .sample(sample),
            .failed(message: "Interrupted", lastSample: sample),
        ] {
            let snapshot = PortholeObservationSnapshot(observation: request.reference, state: state)
            #expect(try PortholeValue.encoding(snapshot)
                .decode(PortholeObservationSnapshot.self) == snapshot)
        }
    }
}
