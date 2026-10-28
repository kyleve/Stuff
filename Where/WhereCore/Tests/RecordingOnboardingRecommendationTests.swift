import Foundation
import Testing
@testable import WhereCore

struct RecordingOnboardingRecommendationTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 100_000)
    private static let currentID = RecordingDeviceID(rawValue: UUID())
    private static let otherID = RecordingDeviceID(rawValue: UUID())

    @Test func phoneDefaultsOnWithoutAnotherRecentRecorder() {
        let recommendation = RecordingOnboardingRecommendation(
            for: installation(kind: .phone),
            devices: [],
            now: Self.now,
        )

        #expect(recommendation.isEnabled)
        #expect(recommendation.recentRecordingDevice == nil)
    }

    @Test(arguments: [RecordingDeviceStatus.recording, .permissionRequired])
    func recentRecorderDefaultsPhoneOff(status: RecordingDeviceStatus) {
        let recent = device(status: status, lastSeenAt: Self.now.addingTimeInterval(-60))

        let recommendation = RecordingOnboardingRecommendation(
            for: installation(kind: .phone),
            devices: [recent],
            now: Self.now,
        )

        #expect(recommendation.isEnabled == false)
        #expect(recommendation.recentRecordingDevice?.id == Self.otherID)
    }

    @Test func activityAtTheTwentyFourHourBoundaryIsRecent() {
        let recent = device(
            status: .recording,
            lastSeenAt: Self.now.addingTimeInterval(-RecordingOnboardingRecommendation
                .recentActivityWindow),
        )

        let recommendation = RecordingOnboardingRecommendation(
            for: installation(kind: .phone),
            devices: [recent],
            now: Self.now,
        )

        #expect(recommendation.isEnabled == false)
    }

    @Test func staleAndRemovedRecordersDoNotSuppressThePhoneDefault() {
        let stale = device(
            status: .recording,
            lastSeenAt: Self.now.addingTimeInterval(
                -RecordingOnboardingRecommendation.recentActivityWindow - 1,
            ),
        )
        let removed = device(
            status: .recording,
            lastSeenAt: Self.now,
            removedAt: Self.now.addingTimeInterval(-1),
        )

        let recommendation = RecordingOnboardingRecommendation(
            for: installation(kind: .phone),
            devices: [stale, removed],
            now: Self.now,
        )

        #expect(recommendation.isEnabled)
    }

    @Test(arguments: [
        RecordingDeviceKind.tablet,
        .computer,
        .watch,
        .other(nil),
    ])
    func nonPhoneDefaultsOff(kind: RecordingDeviceKind) {
        let recommendation = RecordingOnboardingRecommendation(
            for: installation(kind: kind),
            devices: [],
            now: Self.now,
        )

        #expect(recommendation.isEnabled == false)
    }

    private func installation(kind: RecordingDeviceKind) -> CurrentRecordingDevice {
        CurrentRecordingDevice(id: Self.currentID, systemName: "Current", kind: kind)
    }

    private func device(
        status: RecordingDeviceStatus,
        lastSeenAt: Date,
        removedAt: Date? = nil,
    ) -> RecordingDevice {
        RecordingDevice(
            id: Self.otherID,
            systemName: "Other iPhone",
            nickname: nil,
            kind: .phone,
            registeredAt: Self.now.addingTimeInterval(-100_000),
            lastSeenAt: lastSeenAt,
            removedAt: removedAt,
            status: status,
        )
    }
}
