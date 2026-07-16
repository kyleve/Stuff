@testable import SnapshotKit
import Testing

/// Logic tests for the `SnapshotKit` matrix/config. Expanded alongside
/// ``SnapshotConfiguration`` (combination counts, identifier omission, …).
struct SnapshotKitTests {
    @Test func moduleLoads() {
        // Placeholder linkage check; real matrix/identifier assertions land with
        // `SnapshotConfiguration`.
        #expect(SnapshotKit.self == SnapshotKit.self)
    }
}
