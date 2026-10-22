@_spi(Capture) @testable import SnapshotKit
import SwiftUI
import Testing

@MainActor
struct SnapshotPanelCollectionTests {
    @Test func rejectsEmptySheets() {
        #expect(throws: SnapshotPanelCollection.ValidationError.empty) {
            try SnapshotPanelCollection(validating: [])
        }
    }

    @Test func rejectsDuplicateIdentitiesEvenWithDifferentLabels() {
        let identity = SnapshotPanel.ID(rawValue: "same")
        #expect(throws: SnapshotPanelCollection.ValidationError.duplicateIdentity(identity)) {
            try SnapshotPanelCollection(validating: [
                SnapshotPanel(id: identity, label: "One") { Color.red },
                SnapshotPanel(id: identity, label: "Two") { Color.blue },
            ])
        }
    }

    @Test func permitsSharedLabelsWithDistinctIdentities() throws {
        let collection = try SnapshotPanelCollection(validating: [
            SnapshotPanel(id: .init(rawValue: "one"), label: "Same") { Color.red },
            SnapshotPanel(id: .init(rawValue: "two"), label: "Same") { Color.blue },
        ])
        #expect(collection.panels.map(\.id.rawValue) == ["one", "two"])
    }
}
