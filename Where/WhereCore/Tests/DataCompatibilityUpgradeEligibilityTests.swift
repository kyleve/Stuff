import Foundation
import Testing
@testable import WhereCore

struct DataCompatibilityUpgradeEligibilityTests {
    @Test(arguments: [
        RecordingHistoryContribution.Kind.effectiveObservation,
        .explicitSourceChoice,
    ])
    func usesContributedPeriodInsteadOfUploadOrActionTime(kind: RecordingHistoryContribution
        .Kind) throws
    {
        let device = RecordingDeviceID(rawValue: UUID())
        let now = Date(timeIntervalSince1970: 2_000_000)
        let boundary = now
            .addingTimeInterval(-DataCompatibilityUpgradeEligibility.contributionWindow)
        let old = try RecordingHistoryContribution(
            deviceID: device,
            period: .init(start: boundary.addingTimeInterval(-60), end: boundary),
            kind: kind,
        )
        let recent = try RecordingHistoryContribution(
            deviceID: device,
            period: .init(start: boundary, end: boundary.addingTimeInterval(1)),
            kind: kind,
        )
        #expect(!DataCompatibilityUpgradeEligibility.qualifies(
            deviceID: device,
            contributions: [old],
            now: now,
        ))
        #expect(DataCompatibilityUpgradeEligibility.qualifies(
            deviceID: device,
            contributions: [recent],
            now: now,
        ))
        #expect(!DataCompatibilityUpgradeEligibility.qualifies(
            deviceID: .init(rawValue: UUID()),
            contributions: [recent],
            now: now,
        ))
        #expect(!DataCompatibilityUpgradeEligibility.qualifies(
            deviceID: device,
            contributions: [],
            now: now,
        ))
    }
}
