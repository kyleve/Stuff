# SwiftDataInspector todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P1s (Should do)
- test [quick-win]: The bare-`PersistentIdentifier` branch of relationship resolution (`SwiftDataReflection.swift:132`) is untested — the existing relationship test faults a materialized model, which takes the other path. Add a fixture test over an unmaterialized slot. (audit 2026-07-26)
- test [needs-design]: `Tests/SwiftDataInspectorTests.swift` is one 759-line file covering 13 sources, against the 1:1 convention. Split it by concern, optionally adding hosted UI smoke tests. (audit 2026-07-26)
	- test [quick-win]: broken-snapshots — don't add those hosting smoke tests; add image snapshots instead. An image suite, not a "hosts without crashing" test, owns "does this screen render" — the latter asserts nothing about the result. [`SnapshotTests/`](SnapshotTests) already exists with `SwiftDataInspectorSnapshotTests` as the worked example (a local fixture schema, no design-system root); add a file per surface beside it. The root entity list is covered; the paged row table and the relationship drill-in are not. (Same debt as PeriscopeTools' hosting-smoke item — see [`Shared/Periscope/TODOs.md`](../Periscope/TODOs.md).) (pr#101 review)

# Completed issues
