# Inspector todos

The item format and placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md).

## Open issues

### P1s (Should do)

- fix [needs-design]: The second image capture in this bundle's process can
  render a search-field placeholder at a different width. The dark
  `inspectorSurfaces.SwiftData_iPhone_dark` assertion remains quarantined with
  `withKnownIssue` (`SnapshotTests/InspectorSnapshotTests.swift:61-73`,
  `isIntermittent: true`; the light variant at `:36-43` asserts strictly); the
  likely fix is a measured capture-pipeline warm-up in SnapshotKitTesting, not
  re-recording one bistable state. (agent 2026-07-28)
- test [quick-win]: Cover the bare-`PersistentIdentifier` relationship branch
  in `SwiftDataReflection.swift:132-137`; the relationship tests materialize
  the model via key paths and so exercise the `any PersistentModel` branch at
  `:125-130` instead, and `SwiftDataReflectionTests` covers metatype /
  stored-values / fetch only. (audit 2026-07-26)
- test [quick-win]: Add image cases for the paged row table, filesystem root,
  defaults editor, and relationship drill-in. Covered today: the SwiftData
  entity list (light strict, dark quarantined) and the root developer menu
  (light + dark) — one `@Test`, four references
  (`SnapshotTests/InspectorSnapshotTests.swift:18-73`, `:88-125`). Pagination
  is unit-tested but unpinned visually, and `RelationshipView` has a
  `#Preview` (`:130`) with no snapshot case behind it. (pr#101 review)

## Completed issues

- test: Split the inherited SwiftData browsing test monolith by entity,
  reflection, row rendering, pagination, relationship, and mutation concerns.
  (agent 2026-07-30)
