# SwiftDataInspector todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P1s (Should do)
- test [quick-win]: The bare-`PersistentIdentifier` branch of relationship resolution (`SwiftDataReflection.swift:132`) is untested — the existing relationship test faults a materialized model, which takes the other path. Add a fixture test over an unmaterialized slot. (audit 2026-07-26)
- test [needs-design]: `Tests/SwiftDataInspectorTests.swift` is one 759-line file covering 13 sources, against the 1:1 convention. Split it by concern, optionally adding hosted UI smoke tests. (audit 2026-07-26)

# Completed issues
