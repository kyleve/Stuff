import SnapshotKit
import Testing

struct SnapshotReferenceGroupTests {
    @Test(arguments: [
        "",
        ".",
        "..",
        "../flat",
        "/flat",
        "flat/other",
        "Flat",
        "other",
        "flat\n",
        "flat\r\n",
    ])
    func rejectsUnsafeOrReservedGroups(_ value: String) {
        #expect(SnapshotReferenceGroup(rawValue: value) == nil)
    }

    @Test func acceptsStableSlugs() {
        #expect(SnapshotReferenceGroup(rawValue: "flat")?.rawValue == "flat")
        #expect(SnapshotReferenceGroup(rawValue: "paper-2") != nil)
    }
}
