import Foundation
import LifecycleKit
import SwiftUI
import Testing
import WhereCore
import WhereTesting
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
        let model = try WhereModel(
            services: WhereServices(
                store: SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(),
                reminderScheduler: NoopLoggingReminderScheduler(),
                summaryScheduler: NoopDailySummaryScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
            ),
        )
        let view = OnboardingView(bridge: LifecycleStepUIBridge(reason: .userForeground))
            .environment(model)

        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }
}
