import SnapshotKit
import SwiftUI
import Testing

@MainActor
struct SnapshotPanelTests {
    @Test func buildersAreLazyAndFreshOnEveryAccess() {
        var builds = 0
        let panel = SnapshotPanel(id: .init(rawValue: "standard"), label: "Standard") {
            builds += 1
            return Color.red
        }
        let sheet = SnapshotCase.comparison(
            name: "Card",
            configurations: .componentDefaults,
            panels: [panel],
        )
        #expect(builds == 0)
        _ = sheet.comparisonPanels[0].content
        _ = sheet.comparisonPanels[0].content
        #expect(builds == 2)
        #expect(sheet.referenceGroup == .themes)
    }
}
