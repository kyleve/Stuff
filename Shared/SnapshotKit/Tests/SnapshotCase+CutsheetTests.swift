@_spi(Capture) import SnapshotKit
import SwiftUI
import Testing

@MainActor
struct SnapshotCaseCutsheetTests {
    @Test func declaresPanelsWithoutBuildingTheirViews() {
        var builds = 0
        let sheet = SnapshotCase.cutsheet(name: "Card", configurations: .componentDefaults) {
            SnapshotPanel(id: .init(rawValue: "standard"), label: "Standard") {
                builds += 1
                return Color.red
            }
            SnapshotPanel(id: .init(rawValue: "flat"), label: "Flat") {
                builds += 1
                return Color.blue
            }
        }
        #expect(builds == 0)
        guard case let .cutsheet(collection) = sheet.capture else {
            Issue.record("A cutsheet must retain independent capture panels")
            return
        }
        #expect(collection.panels.map(\.id.rawValue) == ["standard", "flat"])
        _ = collection.panels[0].content
        _ = collection.panels[0].content
        _ = collection.panels[1].content
        #expect(builds == 3)
        #expect(sheet.referenceGroup == nil)
    }
}
