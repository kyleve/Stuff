import Foundation
import Testing
@_spi(Testing) @testable import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct OnboardingModelTests {
    @Test func freshInstallationStartsUnonboardedAndUnconfirmed() throws {
        let model = makeModel(
            preferences: makePreferences(),
            contextStore: unconfirmedContextStore(kind: .phone),
        )

        #expect(model.hasOnboarded == false)
        #expect(try model.hasConfirmedRecordingChoice == false)
        #expect(try model.installationRecordingContext.recommendedRecordingEnabled)
    }

    @Test func confirmationPersistsLocalChoiceOutsidePreferences() throws {
        let preferences = makePreferences()
        let contextStore = unconfirmedContextStore(kind: .tablet)
        let model = makeModel(preferences: preferences, contextStore: contextStore)

        let confirmed = try model.confirmInitialRecordingChoice(isEnabled: false)
        model.completeOnboarding()

        #expect(model.hasOnboarded)
        #expect(try model.hasConfirmedRecordingChoice)
        #expect(confirmed.automaticRecordingEnabled == false)

        let relaunched = makeModel(preferences: preferences, contextStore: contextStore)
        #expect(relaunched.hasOnboarded)
        #expect(try relaunched.hasConfirmedRecordingChoice)
        #expect(try relaunched.installationRecordingContext == confirmed)
    }

    @Test func retryPersistsAChangedRecordingChoice() throws {
        let contextStore = unconfirmedContextStore(kind: .phone)
        let model = makeModel(preferences: makePreferences(), contextStore: contextStore)

        _ = try model.confirmInitialRecordingChoice(isEnabled: true)
        let retried = try model.confirmInitialRecordingChoice(isEnabled: false)

        #expect(retried.automaticRecordingEnabled == false)
        #expect(try contextStore.resolve().automaticRecordingEnabled == false)
    }

    @Test func restoredOnboardingFlagDoesNotConfirmANewInstallation() throws {
        let restoredPreferences = makePreferences()
        restoredPreferences.hasOnboarded = true
        let model = makeModel(
            preferences: restoredPreferences,
            contextStore: unconfirmedContextStore(kind: .tablet),
        )

        #expect(model.hasOnboarded)
        #expect(try model.hasConfirmedRecordingChoice == false)
        #expect(try model.installationRecordingContext.recommendedRecordingEnabled == false)
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
                recordingChoice: .unconfirmed,
                isRejoining: false,
            ),
        )
    }
}
