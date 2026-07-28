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
        #expect(!model.hasOnboarded)
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

        // A fresh model over the same preferences sees onboarding as done.
        let relaunched = WhereModel(
            preferences: preferences,
            makeBootstrap: { UnusedBootstrap() },
            logSystem: .isolated(),
        )
        #expect(relaunched.hasOnboarded)
    }
}
