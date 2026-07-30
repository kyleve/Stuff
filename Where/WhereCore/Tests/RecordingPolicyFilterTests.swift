import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingPolicyFilterTests {
    private static let deviceID = RecordingDeviceID(
        rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    )

    private static func sample(
        _ timestamp: String,
        source: SampleSource = .gpsVisit,
        deviceID: RecordingDeviceID? = Self.deviceID,
    ) -> LocationSample {
        LocationSample(
            timestamp: WhereCoreTestSupport.iso(timestamp),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: source,
            recordingDeviceID: deviceID,
        )
    }

    private static func policy(
        _ timestamp: String,
        enabled: Bool,
        id: String,
    ) -> RecordingPolicyChange {
        RecordingPolicyChange(
            id: UUID(uuidString: id)!,
            deviceID: deviceID,
            effectiveAt: WhereCoreTestSupport.iso(timestamp),
            isEnabled: enabled,
        )
    }

    @Test func disabledIntervalIsExcludedAndReenabledIntervalReturns() {
        let before = Self.sample("2026-03-01T08:00:00-08:00")
        let during = Self.sample("2026-03-02T08:00:00-08:00")
        let after = Self.sample("2026-03-03T08:00:00-08:00")
        let policies = [
            Self.policy(
                "2026-03-02T00:00:00-08:00",
                enabled: false,
                id: "10000000-0000-0000-0000-000000000000",
            ),
            Self.policy(
                "2026-03-03T00:00:00-08:00",
                enabled: true,
                id: "20000000-0000-0000-0000-000000000000",
            ),
        ]

        let visible = RecordingPolicyFilter.visibleSamples(
            [before, during, after],
            policyChanges: policies,
        )

        #expect(visible.map(\.id) == [before.id, after.id])
    }

    @Test func cutoffTimestampIsInclusive() {
        let cutoff = Self.policy(
            "2026-03-02T08:00:00-08:00",
            enabled: false,
            id: "10000000-0000-0000-0000-000000000000",
        )
        let sample = Self.sample("2026-03-02T08:00:00-08:00")

        #expect(RecordingPolicyFilter.visibleSamples(
            [sample],
            policyChanges: [cutoff],
        ).isEmpty)
    }

    @Test func legacyAndUserAssertedSamplesRemainVisible() {
        let legacy = Self.sample("2026-03-02T08:00:00-08:00", deviceID: nil)
        let manual = Self.sample(
            "2026-03-02T09:00:00-08:00",
            source: .manual,
            deviceID: Self.deviceID,
        )
        let cutoff = Self.policy(
            "2026-03-01T00:00:00-08:00",
            enabled: false,
            id: "10000000-0000-0000-0000-000000000000",
        )

        let visible = RecordingPolicyFilter.visibleSamples(
            [legacy, manual],
            policyChanges: [cutoff],
        )

        #expect(visible.map(\.id) == [legacy.id, manual.id])
    }

    @Test func equalTimestampPoliciesConvergeByID() {
        let disabled = Self.policy(
            "2026-03-02T00:00:00-08:00",
            enabled: false,
            id: "10000000-0000-0000-0000-000000000000",
        )
        let enabled = Self.policy(
            "2026-03-02T00:00:00-08:00",
            enabled: true,
            id: "20000000-0000-0000-0000-000000000000",
        )
        let sample = Self.sample("2026-03-02T08:00:00-08:00")

        #expect(RecordingPolicyFilter.visibleSamples(
            [sample],
            policyChanges: [enabled, disabled],
        ) == [sample])
    }
}
