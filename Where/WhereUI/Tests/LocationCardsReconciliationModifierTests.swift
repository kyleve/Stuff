import RegionKit
import SwiftUI
import Testing
import UIKit
import WhereCore
@testable import WhereUI

@MainActor
struct LocationCardsReconciliationModifierTests {
    @Test func hostsTheSharedReconciliationSurface() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let presentation = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let current = [RegionDays(region: .california, days: 10)]
        let controller = UIHostingController(
            rootView: Text("Probe")
                .reconcilesLocationCards(
                    current: current,
                    year: 2026,
                    isVisible: false,
                    presentation: presentation,
                ),
        )

        #expect(controller.view != nil)
        #expect(presentation.feedbackTrigger == 0)
    }
}
