@_spi(Capture) import SnapshotKit
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
        #expect(builds == 0)
        _ = panel.content
        _ = panel.content
        #expect(builds == 2)
    }
}
