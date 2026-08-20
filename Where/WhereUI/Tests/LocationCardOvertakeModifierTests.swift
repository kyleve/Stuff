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
        #expect(presentation.overtakeTrigger(for: .california) == 0)
    }

    private struct OvertakeProbe: View {
        let presentation: LocationCardsPresentationModel
        @Namespace private var namespace

        var body: some View {
            Text("Probe")
                .locationCardOvertakeEffect(
                    region: .california,
                    namespace: namespace,
                    presentation: presentation,
                    motion: .standard,
                )
        }
    }
}
