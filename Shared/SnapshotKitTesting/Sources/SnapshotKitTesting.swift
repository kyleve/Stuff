//
//  SnapshotKitTesting.swift
//  SnapshotKitTesting
//

// SnapshotKitTesting is the test-only half of the framework: the capture +
// comparison pipeline and the `assertSnapshots` runner that renders a
// `SnapshotKit.SnapshotConfiguration` matrix. It links the snapshot-comparison
// engine and the accessibility parser, so it is only ever linked by `*SnapshotTests`
// bundles — never a shipping app. See `README.md`.
//
// Re-exported so a test author needs a single `import SnapshotKitTesting` to reach
// both the matrix (`SnapshotKit`) and the assertion/trait API (`SnapshotTesting`).
@_exported import SnapshotKit
@_exported import SnapshotTesting
