# SwiftDataInspector todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P1s (Should do)
- test [quick-win]: The bare-`PersistentIdentifier` branch of relationship resolution (`SwiftDataReflection.swift:132`) is untested — the existing relationship test faults a materialized model, which takes the other path. Add a fixture test over an unmaterialized slot. (audit 2026-07-26)
- test [needs-design]: `Tests/SwiftDataInspectorTests.swift` is one 759-line file covering 13 sources, against the 1:1 convention. Split it by concern, optionally adding hosted UI smoke tests. (audit 2026-07-26)
	- test [needs-design]: broken-snapshots — don't add those hosting smoke tests; take image snapshots instead. The repo convention is now that a `*SnapshotTests` bundle owns "does this screen render", and a "hosts without crashing" test asserts nothing about the result (see the conversion item in [`Shared/Periscope/TODOs.md`](../Periscope/TODOs.md)). This module has no snapshot bundle yet — adding one is tracked in the root [`TODOs.md`](../../TODOs.md) broken-snapshots item, which also wants `SwiftDataInspectorSnapshotTests` moved here out of `WhereUI`. Do the split against that bundle rather than seeding smoke tests it would immediately replace. (pr#101 review)

# Completed issues
