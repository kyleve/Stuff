import Foundation
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
import WhereUI

@MainActor
struct OnboardingModelTests {
    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    @Test func hasOnboardedDefaultsFalse() {
        let model = WhereModel(preferences: makePreferences())
        #expect(!model.hasOnboarded)
    }

    @Test func completeOnboardingPersists() {
        let preferences = makePreferences()
        let model = WhereModel(preferences: preferences)
        model.completeOnboarding()
        #expect(model.hasOnboarded)

        // A fresh model over the same preferences sees onboarding as done.
        let relaunched = WhereModel(preferences: preferences)
        #expect(relaunched.hasOnboarded)
    }
}

@MainActor
struct OnboardingViewTests {
    @Test func onboardingViewRenders() throws {
        // Onboarding reads the app model from the environment and is handed
        // the session directly (as the launch's parked phase does); the
        // injected services build the session up front.
        let model = WhereModel(services: PreviewSupport.previewServices())
        let session = try #require(model.session)
        let view = OnboardingView(
            handle: OnboardingHandle(),
            session: session,
        )
        .environment(model)

        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }
}
