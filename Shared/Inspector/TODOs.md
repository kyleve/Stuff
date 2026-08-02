# Inspector todos

The item format and placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md).

## Open issues

### P1s (Should do)

- fix [needs-design]: The second image capture in this bundle's process can
  render a search-field placeholder at a different width. The dark
  `inspectorSurfaces.SwiftData_iPhone_dark` assertion remains quarantined with
  `withKnownIssue`; the likely fix is a measured capture-pipeline warm-up in
  SnapshotKitTesting, not re-recording one bistable state. (agent 2026-07-28)
- test [quick-win]: Cover the bare-`PersistentIdentifier` relationship branch
  in `SwiftDataReflection.swift`; current relationship tests materialize the
  model and exercise the other branch. (audit 2026-07-26)
- test [quick-win]: Add image cases for the paged row table, filesystem root,
  defaults editor, and relationship drill-in. The entity list and developer
  menu are covered. (pr#101 review)

## Completed issues

- test: Split the inherited SwiftData browsing test monolith by entity,
  reflection, row rendering, pagination, relationship, and mutation concerns.
  (agent 2026-07-30)
