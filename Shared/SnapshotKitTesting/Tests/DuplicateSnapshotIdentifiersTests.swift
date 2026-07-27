import SnapshotKitTesting
import SwiftUI
import Testing

/// Guards the collision detection behind `assertSnapshots(of:)`'s
/// duplicate-identifier guard: two variants that would render to the same
/// reference-image name must be flagged before anything is asserted, because
/// whichever records first, the other silently compares against its image.
@MainActor
struct DuplicateSnapshotIdentifiersTests {
    @Test func flagsTwoCasesWithTheSameName() {
        let cases = [
            SnapshotCase(name: "Badge", configurations: [SnapshotConfiguration()]) { Color.red },
            SnapshotCase(name: "Badge", configurations: [SnapshotConfiguration()]) { Color.blue },
        ]
        #expect(duplicateSnapshotIdentifiers(in: cases) == ["Badge"])
    }

    @Test func flagsOneCaseWithDuplicateConfigurations() {
        let dark = SnapshotConfiguration(colorScheme: .dark)
        let cases = [
            SnapshotCase(name: "Badge", configurations: [dark, dark]) { Color.red },
        ]
        #expect(duplicateSnapshotIdentifiers(in: cases) == ["Badge_dark"])
    }

    /// The underscore-joined format lets distinct declarations collide: a case
    /// named `Badge` in dark mode renders to the same reference as a case
    /// literally named `Badge_dark` — the guard must catch that spelling too.
    @Test func flagsACollisionAcrossDifferentlyNamedCases() {
        let cases = [
            SnapshotCase(
                name: "Badge",
                configurations: [SnapshotConfiguration(colorScheme: .dark)],
            ) { Color.red },
            SnapshotCase(name: "Badge_dark", configurations: [SnapshotConfiguration()]) {
                Color.blue
            },
        ]
        #expect(duplicateSnapshotIdentifiers(in: cases) == ["Badge_dark"])
    }

    @Test func distinctIdentifiersProduceNoDuplicates() {
        let cases = [
            SnapshotCase(
                name: "Badge",
                configurations: [
                    SnapshotConfiguration(),
                    SnapshotConfiguration(colorScheme: .dark),
                ],
            ) { Color.red },
            SnapshotCase(name: "Card", configurations: [SnapshotConfiguration()]) { Color.blue },
        ]
        #expect(duplicateSnapshotIdentifiers(in: cases).isEmpty)
    }
}
