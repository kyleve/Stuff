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
            rootView: OvertakeProbe(presentation: presentation),
        )

        #expect(controller.view != nil)
        #expect(presentation.overtakeTrigger == 0)
    }

    private struct OvertakeProbe: View {
        let presentation: LocationCardsPresentationModel
        var body: some View {
            Text("Probe")
                .locationCardOvertakeEffect(
                    region: .california,
                    presentation: presentation,
                    motion: .standard,
                )
        }
    }
}
