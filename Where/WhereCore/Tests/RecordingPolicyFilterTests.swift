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
        parentIDs: [String] = [],
        revision: Int64 = 0,
    ) -> RecordingPolicyChange {
        RecordingPolicyChange(
            id: UUID(uuidString: id)!,
            deviceID: deviceID,
            parentIDs: parentIDs.compactMap(UUID.init(uuidString:)),
            revision: revision,
            issuedAt: WhereCoreTestSupport.iso(timestamp),
            issuedByDeviceID: deviceID,
            effectiveAt: WhereCoreTestSupport.iso(timestamp),
            state: enabled ? .on : .off,
            reason: .userCommand,
        )
    }

    @Test func disabledIntervalIsExcludedAndReenabledIntervalReturns() {
        let before = Self.sample("2026-03-01T08:00:00-08:00")
        let during = Self.sample("2026-03-02T08:00:00-08:00")
        let after = Self.sample("2026-03-03T08:00:00-08:00")
        let policies = [
            Self.policy(
                "2026-03-01T00:00:00-08:00",
                enabled: true,
                id: "05000000-0000-0000-0000-000000000000",
            ),
            Self.policy(
                "2026-03-02T00:00:00-08:00",
                enabled: false,
                id: "10000000-0000-0000-0000-000000000000",
                parentIDs: ["05000000-0000-0000-0000-000000000000"],
                revision: 1,
            ),
            Self.policy(
                "2026-03-03T00:00:00-08:00",
                enabled: true,
                id: "20000000-0000-0000-0000-000000000000",
                parentIDs: ["10000000-0000-0000-0000-000000000000"],
                revision: 2,
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

    @Test func equalRevisionPoliciesPreferTheMoreRestrictiveState() {
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
        ).isEmpty)
    }

    @Test func causalWinnerIsNotReversedByAnotherDevicesLaterClock() {
        let initial = Self.policy(
            "2026-02-28T00:00:00-08:00",
            enabled: true,
            id: "10000000-0000-0000-0000-000000000000",
        )
        let causallyLaterDisable = Self.policy(
            "2026-03-02T00:00:00-08:00",
            enabled: false,
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: ["30000000-0000-0000-0000-000000000000"],
            revision: 2,
        )
        let clockSkewedOlderEnable = Self.policy(
            "2026-03-03T00:00:00-08:00",
            enabled: true,
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: ["10000000-0000-0000-0000-000000000000"],
            revision: 1,
        )
        let sample = Self.sample("2026-03-04T08:00:00-08:00")

        #expect(RecordingPolicyFilter.visibleSamples(
            [sample],
            policyChanges: [initial, clockSkewedOlderEnable, causallyLaterDisable],
        ).isEmpty)
    }

    @Test func deviceStampedSampleFailsClosedUntilItsPolicyArrives() {
        let stamped = Self.sample("2026-03-02T08:00:00-08:00")
        let legacy = Self.sample("2026-03-02T09:00:00-08:00", deviceID: nil)

        let visible = RecordingPolicyFilter.visibleSamples(
            [stamped, legacy],
            policyChanges: [],
        )

        #expect(visible == [legacy])
    }

    @Test func deviceStampedSampleFailsClosedWhilePolicyRevisionsHaveAGap() {
        let initial = Self.policy(
            "2026-03-01T00:00:00-08:00",
            enabled: true,
            id: "10000000-0000-0000-0000-000000000000",
        )
        let laterEnable = Self.policy(
            "2026-03-03T00:00:00-08:00",
            enabled: true,
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: ["10000000-0000-0000-0000-000000000000"],
            revision: 2,
        )
        let stamped = Self.sample("2026-03-04T08:00:00-08:00")
        let legacy = Self.sample("2026-03-04T09:00:00-08:00", deviceID: nil)

        let visible = RecordingPolicyFilter.visibleSamples(
            [stamped, legacy],
            policyChanges: [initial, laterEnable],
        )

        #expect(visible == [legacy])
    }

    @Test func backdatedChildCannotReExposeSamplesBeforeItsOffParent() {
        let initial = Self.policy(
            "2026-03-01T00:00:00-08:00",
            enabled: true,
            id: "10000000-0000-0000-0000-000000000000",
        )
        let off = Self.policy(
            "2026-03-03T00:00:00-08:00",
            enabled: false,
            id: "20000000-0000-0000-0000-000000000000",
            parentIDs: ["10000000-0000-0000-0000-000000000000"],
            revision: 1,
        )
        let backdatedEnable = Self.policy(
            "2026-03-02T00:00:00-08:00",
            enabled: true,
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: ["20000000-0000-0000-0000-000000000000"],
            revision: 2,
        )
        let sample = Self.sample("2026-03-02T08:00:00-08:00")

        #expect(RecordingPolicyFilter.visibleSamples(
            [sample],
            policyChanges: [initial, off, backdatedEnable],
        ).isEmpty)
    }

    @Test func archivedAuthorityExcludesLaterSamples() throws {
        let sample = Self.sample("2026-03-03T08:00:00-08:00")
        let archiveID = try #require(
            UUID(uuidString: "20000000-0000-0000-0000-000000000000"),
        )
        let archived = try RecordingPolicyChange(
            id: archiveID,
            deviceID: Self.deviceID,
            parentIDs: [#require(UUID(uuidString: "10000000-0000-0000-0000-000000000000"))],
            revision: 1,
            issuedAt: WhereCoreTestSupport.iso("2026-03-02T00:00:00-08:00"),
            issuedByDeviceID: Self.deviceID,
            effectiveAt: WhereCoreTestSupport.iso("2026-03-02T00:00:00-08:00"),
            state: .archived,
            reason: .archive,
        )

        #expect(RecordingPolicyFilter.visibleSamples(
            [sample],
            policyChanges: [
                Self.policy(
                    "2026-03-01T00:00:00-08:00",
                    enabled: true,
                    id: "10000000-0000-0000-0000-000000000000",
                ),
                archived,
            ],
        ).isEmpty)
    }

    @Test func accountResetKeepsLatePreResetSamplesErasedAfterReenable() throws {
        let initial = Self.policy(
            "2026-03-01T00:00:00-08:00",
            enabled: true,
            id: "10000000-0000-0000-0000-000000000000",
        )
        let resetAt = WhereCoreTestSupport.iso("2026-03-03T00:00:00-08:00")
        let reset = try RecordingPolicyChange(
            id: #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000")),
            deviceID: Self.deviceID,
            parentIDs: [initial.id],
            revision: 1,
            issuedAt: resetAt,
            issuedByDeviceID: Self.deviceID,
            effectiveAt: resetAt,
            state: .off,
            reason: .accountReset,
        )
        let reenabled = Self.policy(
            "2026-03-04T00:00:00-08:00",
            enabled: true,
            id: "30000000-0000-0000-0000-000000000000",
            parentIDs: ["20000000-0000-0000-0000-000000000000"],
            revision: 2,
        )
        let latePreReset = Self.sample("2026-03-02T08:00:00-08:00")
        let afterReenable = Self.sample("2026-03-05T08:00:00-08:00")

        let visible = RecordingPolicyFilter.visibleSamples(
            [latePreReset, afterReenable],
            policyChanges: [initial, reset, reenabled],
        )

        #expect(visible.map(\.id) == [afterReenable.id])
    }

    @Test func concurrentAccountResetOutranksBackupReplacement() throws {
        let initial = Self.policy(
            "2026-03-01T00:00:00-08:00",
            enabled: true,
            id: "05000000-0000-0000-0000-000000000000",
        )
        let commandDate = WhereCoreTestSupport.iso("2026-03-03T00:00:00-08:00")
        let reset = try RecordingPolicyChange(
            id: #require(UUID(uuidString: "10000000-0000-0000-0000-000000000000")),
            deviceID: Self.deviceID,
            parentIDs: [initial.id],
            revision: 1,
            issuedAt: commandDate,
            issuedByDeviceID: Self.deviceID,
            effectiveAt: commandDate,
            state: .off,
            reason: .accountReset,
        )
        // Its lexically later id would win the old UUID tie-break, dropping the reset floor.
        let replacement = try RecordingPolicyChange(
            id: #require(UUID(uuidString: "20000000-0000-0000-0000-000000000000")),
            deviceID: Self.deviceID,
            parentIDs: [initial.id],
            revision: 1,
            issuedAt: commandDate,
            issuedByDeviceID: Self.deviceID,
            effectiveAt: commandDate,
            state: .off,
            reason: .backupReplace,
        )
        let latePreReset = Self.sample("2026-03-02T08:00:00-08:00")

        #expect(RecordingPolicyFilter.visibleSamples(
            [latePreReset],
            policyChanges: [replacement, initial, reset],
        ).isEmpty)
    }
}
