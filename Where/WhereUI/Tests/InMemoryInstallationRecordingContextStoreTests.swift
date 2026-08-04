import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) import WhereUI

@MainActor
struct InMemoryInstallationRecordingContextStoreTests {
    @Test func confirmationStaysInMemory() throws {
        let context = unconfirmedContext()
        let store = InMemoryInstallationRecordingContextStore(
            context: context,
            makeUUID: { Self.replacementDeviceID },
            now: { Self.replacementRegisteredAt },
        )

        let confirmed = try store.confirmInitialRecording(isEnabled: false)

        #expect(confirmed.automaticRecordingEnabled == false)
        #expect(confirmed.registeredAt == Self.registeredAt)
        #expect(try store.resolve() == confirmed)
    }

    @Test func settingsCanChangeTheConfirmedLocalChoice() throws {
        let store = InMemoryInstallationRecordingContextStore(context: .testing)

        try store.setAutomaticRecordingEnabled(false)

        #expect(try store.resolve().automaticRecordingEnabled == false)
    }

    @Test func resetCreatesANewOrdinaryUnconfirmedIdentity() throws {
        let store = makeStore(context: .testing)

        try store.reset()

        #expect(store.onboardingContext.currentDevice.id.rawValue == Self.replacementDeviceID)
        #expect(store.onboardingContext.registeredAt == Self.replacementRegisteredAt)
        #expect(store.onboardingContext.automaticRecordingEnabled == nil)
        #expect(store.onboardingContext.isRejoining == false)
    }

    @Test func rejoinCreatesANewConservativeUnconfirmedIdentity() throws {
        let store = makeStore(context: .testing)

        let rejoined = try store.rejoin()

        #expect(rejoined.currentDevice.id.rawValue == Self.replacementDeviceID)
        #expect(rejoined.automaticRecordingEnabled == nil)
        #expect(rejoined.isRejoining)
        #expect(rejoined.recommendedRecordingEnabled == false)
    }

    @Test func laterConfirmationCannotRewriteTheInitialChoice() throws {
        let store = InMemoryInstallationRecordingContextStore(context: .testing)

        let repeated = try store.confirmInitialRecording(isEnabled: false)

        #expect(repeated == .testing)
        #expect(repeated.automaticRecordingEnabled == true)
    }

    private func makeStore(
        context: InstallationRecordingContext,
    ) -> InMemoryInstallationRecordingContextStore {
        InMemoryInstallationRecordingContextStore(
            context: context,
            makeUUID: { Self.replacementDeviceID },
            now: { Self.replacementRegisteredAt },
        )
    }

    private func unconfirmedContext() -> InstallationRecordingContext {
        InstallationRecordingContext(
            currentDevice: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: Self.deviceID),
                systemName: "iPad",
                kind: .tablet,
            ),
            registeredAt: Self.registeredAt,
            automaticRecordingEnabled: nil,
            isRejoining: false,
        )
    }

    private static let deviceID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private static let replacementDeviceID = UUID(
        uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
    )!
    private static let registeredAt = Date(timeIntervalSinceReferenceDate: 100)
    private static let replacementRegisteredAt = Date(timeIntervalSinceReferenceDate: 300)
}
