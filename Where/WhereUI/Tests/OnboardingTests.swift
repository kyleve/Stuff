import Testing
@_spi(Testing) import WhereCore
import WhereUI

@MainActor
struct OnboardingModelTests {
    @Test func hasOnboardedDefaultsFalse() {
        let model = WhereModel(
            preferences: makePreferences(),
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )
        #expect(model.hasOnboarded == false)
        #expect(model.hasConfirmedRecordingChoice == false)
    }

    @Test func completeOnboardingPersists() {
        let preferences = makePreferences()
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )
        model.completeOnboarding()
        #expect(model.hasOnboarded)
        #expect(model.hasConfirmedRecordingChoice)

        // A fresh model over the same preferences sees onboarding as done.
        let relaunched = WhereModel(
            preferences: preferences,
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )
        #expect(relaunched.hasOnboarded)
        #expect(relaunched.hasConfirmedRecordingChoice)
    }

    @Test func recordingChoiceCanBeConfirmedWithoutRepeatingOnboarding() {
        let preferences = makePreferences()
        preferences.hasOnboarded = true
        let model = WhereModel(
            preferences: preferences,
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )

        model.confirmRecordingChoice()

        #expect(model.hasOnboarded)
        #expect(model.hasConfirmedRecordingChoice)
    }
}
