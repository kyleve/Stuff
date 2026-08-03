import Foundation
import Testing
@testable import WhereCore

struct InstallationRecordingContextTests {
    @Test func recommendationComesFromTheDeviceKind() {
        let phone = context(kind: .phone)
        let tablet = context(kind: .tablet)

        #expect(phone.recommendedRecordingEnabled)
        #expect(tablet.recommendedRecordingEnabled == false)
    }

    @Test func confirmationPreservesIdentityAndCarriesAStablePolicyToken() throws {
        let proposed = context(kind: .tablet)
        let assignmentChangeID = try #require(
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
        )

        let confirmed = proposed.confirmingInitialRecording(
            isEnabled: false,
            assignmentChangeID: assignmentChangeID,
            confirmedAt: Self.confirmedAt,
        )

        #expect(confirmed.currentDevice == proposed.currentDevice)
        #expect(confirmed.registeredAt == proposed.registeredAt)
        #expect(confirmed.initialRecordingChoice?.isEnabled == false)
        #expect(confirmed.initialRecordingChoice?.assignmentChangeID == assignmentChangeID)
        #expect(confirmed.initialRecordingChoice?.confirmedAt == Self.confirmedAt)
    }

    private func context(kind: RecordingDeviceKind) -> InstallationRecordingContext {
        InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: UUID()),
                systemName: kind == .tablet ? "iPad" : "iPhone",
                kind: kind,
            ),
            registeredAt: Self.registeredAt,
            initialRecordingChoice: nil,
        )
    }

    private static let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
    private static let confirmedAt = Date(timeIntervalSinceReferenceDate: 200)
}
