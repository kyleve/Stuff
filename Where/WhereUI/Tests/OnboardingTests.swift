import Foundation
import LifecycleKit
import SwiftUI
import Testing
import WhereCore
import WhereTesting
import WhereUI

@MainActor
struct OnboardingModelTests {
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func hasOnboardedDefaultsFalse() {
        let model = WhereModel(defaults: ephemeralDefaults())
        #expect(!model.hasOnboarded)
    }

    @Test func completeOnboardingPersists() {
        let defaults = ephemeralDefaults()
        let model = WhereModel(defaults: defaults)
        model.completeOnboarding()
        #expect(model.hasOnboarded)

        // A fresh model over the same defaults sees onboarding as done.
        let relaunched = WhereModel(defaults: defaults)
        #expect(relaunched.hasOnboarded)
    }
}

@MainActor
struct OnboardingViewTests {
    @Test func onboardingViewRenders() throws {
        let model = try WhereModel(
            controller: WhereController(
                store: SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(),
                reminderScheduler: NoopLoggingReminderScheduler(),
                summaryScheduler: NoopDailySummaryScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
            ),
        )
        let view = OnboardingView(handle: StepHandle(reason: .userForeground))
            .environment(model)

        try show(UIHostingController(rootView: view)) { hosted in
            waitForOneRunloop()
            #expect(hosted.view != nil)
        }
    }
}
