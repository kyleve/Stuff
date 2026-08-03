import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) import WhereUI

@MainActor
struct InMemoryInstallationRecordingContextStoreTests {
    @Test func confirmationStaysInMemory() throws {
        let context = InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: Self.deviceID),
                systemName: "iPad",
                kind: .tablet,
            ),
            registeredAt: Self.registeredAt,
            initialRecordingChoice: nil,
        )
        let store = InMemoryInstallationRecordingContextStore(
            context: context,
            makeUUID: { Self.assignmentChangeID },
            now: { Self.confirmedAt },
        )

        let confirmed = try store.confirmInitialRecording(isEnabled: false)

        #expect(confirmed.initialRecordingChoice?.assignmentChangeID == Self.assignmentChangeID)
        #expect(confirmed.registeredAt == Self.registeredAt)
        #expect(confirmed.initialRecordingChoice?.confirmedAt == Self.confirmedAt)
        #expect(try store.resolve() == confirmed)
    }

    @Test func resetCreatesANewUnconfirmedIdentity() throws {
        let store = InMemoryInstallationRecordingContextStore(
            context: .testing,
            makeUUID: { Self.resetDeviceID },
            now: { Self.resetRegisteredAt },
        )

        try store.reset()

        #expect(store.onboardingContext.currentDevice.id.rawValue == Self.resetDeviceID)
        #expect(store.onboardingContext.registeredAt == Self.resetRegisteredAt)
        #expect(store.onboardingContext.initialRecordingChoice == nil)
    }

    @Test func laterConfirmationCannotRewriteTheInitialPolicyEvent() throws {
        let store = InMemoryInstallationRecordingContextStore(
            context: .testing,
            makeUUID: { Self.resetDeviceID },
            now: { Self.confirmedAt },
        )

        let repeated = try store.confirmInitialRecording(isEnabled: false)

        #expect(repeated == .testing)
        #expect(repeated.initialRecordingChoice?.isEnabled == true)
    }

    private static let deviceID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private static let assignmentChangeID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
    )!
    private static let resetDeviceID = UUID(
        uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
    )!
    private static let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
    private static let confirmedAt = Date(timeIntervalSinceReferenceDate: 200)
    private static let resetRegisteredAt = Date(timeIntervalSinceReferenceDate: 300)
}
