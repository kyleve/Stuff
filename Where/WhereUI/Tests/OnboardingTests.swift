import Foundation
import Testing
@_spi(Testing) @testable import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct OnboardingModelTests {
    @Test func freshInstallationStartsUnonboardedAndUnconfirmed() {
        let model = makeModel(
            preferences: makePreferences(),
            contextStore: unconfirmedContextStore(kind: .phone),
        )

        #expect(model.hasOnboarded == false)
        #expect(model.hasConfirmedRecordingChoice == false)
        #expect(model.installationRecordingContext.recommendedRecordingEnabled)
    }

    @Test func confirmationPersistsChoiceAndPolicyTokenOutsidePreferences() throws {
        let preferences = makePreferences()
        let contextStore = unconfirmedContextStore(kind: .tablet)
        let model = makeModel(preferences: preferences, contextStore: contextStore)

        let confirmed = try model.confirmInitialRecordingChoice(isEnabled: false)
        model.completeOnboarding()

        #expect(model.hasOnboarded)
        #expect(model.hasConfirmedRecordingChoice)
        #expect(confirmed.initialRecordingChoice?.isEnabled == false)
        #expect(confirmed.initialRecordingChoice?.policyChangeID != nil)

        let relaunched = makeModel(preferences: preferences, contextStore: contextStore)
        #expect(relaunched.hasOnboarded)
        #expect(relaunched.hasConfirmedRecordingChoice)
        #expect(relaunched.installationRecordingContext == confirmed)
    }

    @Test func restoredOnboardingFlagDoesNotConfirmANewInstallation() {
        let restoredPreferences = makePreferences()
        restoredPreferences.hasOnboarded = true
        let model = makeModel(
            preferences: restoredPreferences,
            contextStore: unconfirmedContextStore(kind: .tablet),
        )

        #expect(model.hasOnboarded)
        #expect(model.hasConfirmedRecordingChoice == false)
        #expect(model.installationRecordingContext.recommendedRecordingEnabled == false)
    }

    private func makeModel(
        preferences: WherePreferences,
        contextStore: InMemoryInstallationRecordingContextStore,
    ) -> WhereModel {
        WhereModel(
            preferences: preferences,
            installationContextStore: contextStore,
            makeBootstrap: { _ in UnusedBootstrap() },
            logSystem: .isolated(),
        )
    }

    private func unconfirmedContextStore(
        kind: RecordingDeviceKind,
    ) -> InMemoryInstallationRecordingContextStore {
        InMemoryInstallationRecordingContextStore(
            context: InstallationRecordingContext(
                currentDevice: CurrentRecordingDevice(
                    id: RecordingDeviceID(rawValue: UUID()),
                    systemName: kind == .tablet ? "iPad" : "iPhone",
                    kind: kind,
                ),
                registeredAt: Date(timeIntervalSinceReferenceDate: 0),
                initialRecordingChoice: nil,
            ),
        )
    }
}
