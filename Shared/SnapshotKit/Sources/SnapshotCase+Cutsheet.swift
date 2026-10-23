extension SnapshotCase {
    /// Describes independently captured panels, composed into one comparison sheet.
    /// Unlike a SwiftUI grid, every panel receives its own host and comparison budget.
    /// Empty sheets and duplicate panel identities are programmer errors.
    @MainActor public static func cutsheet(
        name: String,
        configurations: [SnapshotConfiguration],
        referenceGroup: SnapshotReferenceGroup? = nil,
        measurementReadiness: SnapshotMeasurementReadiness = .sameAsCapture,
        onReadyToMeasure: (@MainActor () async -> Void)? = nil,
        settle: SnapshotSettle = .settled,
        onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
        @SnapshotPanelBuilder panels: () -> [SnapshotPanel],
    ) -> SnapshotCase {
        let collection: SnapshotPanelCollection
        do {
            collection = try SnapshotPanelCollection(validating: panels())
        } catch {
            preconditionFailure("Invalid cutsheet \(name): \(error)")
        }
        return SnapshotCase(
            name: name,
            configurations: configurations,
            referenceGroup: referenceGroup,
            measurementReadiness: measurementReadiness,
            onReadyToMeasure: onReadyToMeasure,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
            panels: collection,
        )
    }
}
