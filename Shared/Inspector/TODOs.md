# Inspector todos

The item format and placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md).

## Open issues

### P1s (Should do)

- fix [needs-design]: The second image capture in this bundle's process can
  render a search-field placeholder at a different width. The dark
  `inspectorSurfaces.SwiftData_iPhone_dark` assertion remains quarantined with
  `withKnownIssue(..., isIntermittent: true)`
  (`SnapshotTests/InspectorSnapshotTests.swift:61-73`); the likely fix is a
  measured capture-pipeline warm-up in SnapshotKitTesting, not re-recording one
  bistable state. It is one of only two `withKnownIssue` quarantines in the repo
  (the other guards the Elsewhere inflection bug in WhereUI).
  (agent 2026-07-28; re-verified 2026-08-09)
- test [quick-win]: Cover the bare-`PersistentIdentifier` relationship branch
  in `SwiftDataReflection.swift:132-137` (`classify` when the relationship value
  is a bare identifier); `InspectorSwiftDataRelationshipTests` materializes
  `TestParent`/`TestChild` and only ever exercises the other branch, and
  `SwiftDataReflectionTests` covers attribute reads and fetch helpers.
  (audit 2026-07-26; re-verified 2026-08-09)
- test [quick-win]: Add image cases for the paged row table, filesystem root,
  defaults editor, and relationship drill-in. The bundle still has exactly one
  case, `inspectorSurfaces`, producing four references — Root light/dark
  (`SnapshotTests/InspectorSnapshotTests.swift:118-125`) and SwiftData light
  plus the quarantined dark (`:36-73`). (pr#101 review; re-verified 2026-08-09)

## Completed issues

- test: Split the inherited SwiftData browsing test monolith by entity,
  reflection, row rendering, pagination, relationship, and mutation concerns.
  (agent 2026-07-30)
