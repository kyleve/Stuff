import Testing
@_spi(Testing) import WhereCore
import WhereUI

@MainActor
struct OnboardingModelTests {
    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    @Test func hasOnboardedDefaultsFalse() {
        let model = WhereModel(preferences: makePreferences(), logSystem: .isolated())
        #expect(!model.hasOnboarded)
    }

    @Test func completeOnboardingPersists() {
        let preferences = makePreferences()
        let model = WhereModel(preferences: preferences, logSystem: .isolated())
        model.completeOnboarding()
        #expect(model.hasOnboarded)

        // A fresh model over the same preferences sees onboarding as done.
        let relaunched = WhereModel(preferences: preferences, logSystem: .isolated())
        #expect(relaunched.hasOnboarded)
    }
}
