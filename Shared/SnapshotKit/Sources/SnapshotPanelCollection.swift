/// A validated set of independent captures. Only the cutsheet factory creates it;
/// SnapshotKitTesting and Flyover can read it through the capture SPI.
@_spi(Capture) public struct SnapshotPanelCollection {
    public let panels: [SnapshotPanel]

    init(validating panels: [SnapshotPanel]) throws {
        guard !panels.isEmpty else { throw ValidationError.empty }
        var identities = Set<SnapshotPanel.ID>()
        for panel in panels {
            guard identities.insert(panel.id).inserted else {
                throw ValidationError.duplicateIdentity(panel.id)
            }
        }
        self.panels = panels
    }

    enum ValidationError: Error, Equatable {
        case empty
        case duplicateIdentity(SnapshotPanel.ID)
    }
}
