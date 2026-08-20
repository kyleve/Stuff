import RegionKit
import SwiftUI
import Testing
import UIKit
import WhereCore
@testable import WhereUI

@MainActor
struct LocationCardOvertakeModifierTests {
    @Test func hostsAtTheNeutralKeyframeState() {
        let presentation = LocationCardsPresentationModel(
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
            year: 2026,
        )
        let controller = UIHostingController(
            rootView: Text("Probe")
                .locationCardOvertakeEffect(
                    region: .california,
                    presentation: presentation,
                    motion: .standard,
                ),
        )

        #expect(controller.view != nil)
        #expect(presentation.overtakeTrigger(for: .california) == 0)
    }
}
