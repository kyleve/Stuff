import SnapshotKit
import SwiftUI
import Testing

struct SnapshotPanelBuilderTests {
    @SnapshotPanelBuilder
    private func panels(includeOptional: Bool, firstBranch: Bool) -> [SnapshotPanel] {
        SnapshotPanel(id: .init(rawValue: "first"), label: "First") { Color.red }
        if includeOptional {
            SnapshotPanel(id: .init(rawValue: "optional"), label: "Optional") { Color.blue }
        }
        if firstBranch {
            SnapshotPanel(id: .init(rawValue: "yes"), label: "Yes") { Color.red }
        } else {
            SnapshotPanel(id: .init(rawValue: "no"), label: "No") { Color.red }
        }
        for value in ["a", "b"] {
            SnapshotPanel(id: .init(rawValue: value), label: value) { Color.green }
        }
    }

    @Test func preservesDeclarationOrderAcrossControlFlow() {
        #expect(panels(includeOptional: true, firstBranch: true).map(\.id.rawValue)
            == ["first", "optional", "yes", "a", "b"])
        #expect(panels(includeOptional: false, firstBranch: false).map(\.id.rawValue)
            == ["first", "no", "a", "b"])
    }
}
