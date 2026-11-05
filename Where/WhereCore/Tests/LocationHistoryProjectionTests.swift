import Foundation
import Testing
@testable import WhereCore

struct LocationHistoryProjectionTests {
    @Test func reviewContextRetainsSelectedDatesAndRelevantResetTombstones() throws {
        let samples = try RecordingFlightTestSupport.samples(
            FlightTrajectoryFixtures.shortSparseFlight()
                + [FlightTrajectoryFixtures.sample(999, minutes: 10000, east: 0)],
        )
        let selected = try RecordingFlightTestSupport.projection(
            samples,
            period: RecordingFlightTestSupport.period(0, 40),
        )
        let revisions = samples.map {
            SampleAttributionRevision(
                id: .init(rawValue: UUID()),
                sampleID: $0.id,
                updatedAt: FlightTrajectoryFixtures.date(minutes: 50),
                replacementRegions: nil,
            )
        }
        let original = LocationHistoryProjection(
            samples: selected.samples,
            revisions: revisions,
            contract: selected.contract,
        )
        let period = try RecordingFlightTestSupport.period(25, 30)
        let clipped = try original.clipped(to: period)
        #expect(clipped.samples == [selected.samples[2]])
        #expect(clipped.revisions == Array(revisions.dropLast()))
        #expect(clipped.samples.first?.day == .recording(.init(year: 2026, month: 1, day: 1)))
        guard case let .recording(selection) = clipped.contract else {
            Issue.record("A clipped review must retain recording selection metadata")
            return
        }
        #expect(selection.controls
            .allSatisfy { $0.period.start >= period.start && $0.period.end <= period.end })
        #expect(selection.policyVersion == RecordingEvidencePolicy.version)
        #expect(original.samples.count == samples.count - 1)
        #expect(original.revisions.count == revisions.count)
    }
}
