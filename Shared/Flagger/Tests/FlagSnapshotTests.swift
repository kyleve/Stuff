@testable import Flagger
import Testing

struct FlagSnapshotTests {
    @Test
    func frozenOverrideReportsAPendingChange() {
        let snapshot = makeSnapshot(storedValue: .boolean(true), isFrozen: true)

        #expect(snapshot.isDefault == false)
        #expect(snapshot.hasPendingChange)
    }

    private func makeSnapshot(storedValue: JSONValue?, isFrozen: Bool) -> FlagSnapshot {
        FlagSnapshot(
            id: FlagID(rawValue: "flag"),
            propertyName: "flag",
            name: "Flag",
            detail: nil,
            source: FeatureFlagSourceMetadata(id: FlagSourceID("source"), name: "Source"),
            group: FeatureFlagGroupMetadata(
                id: FeatureFlagGroupID("group"),
                name: "Group",
                detail: nil,
            ),
            behavior: .readOnceOnLaunch,
            defaultValue: .boolean(false),
            storedValue: storedValue,
            effectiveValue: .boolean(false),
            isFrozen: isFrozen,
            failure: nil,
        )
    }
}
