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
  (the other guards the Elsewhere inflection bug in WhereUI, at
  `Where/WhereUI/Tests/WhereFormatTests.swift:89`) — re-counted repo-wide
  2026-08-23 and still exactly two.
  (agent 2026-07-28; re-verified 2026-08-23)
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
  plus the quarantined dark (`:36-73`). (pr#101 review; re-verified 2026-08-16)

### P2s (Nice to have)

- fix [quick-win]: Three of the four fetch helpers swallow their errors into an
  empty result, and the file itself argues they shouldn't. `inspectorCount`
  returns `0` (`Sources/ModelContext+InspectorFetch.swift:9`), `inspectorFetch`
  returns `[]` (`:52`), and `inspectorModels` returns `[:]` (`:76`), each via
  `try?` with no log — so a store that has become unreadable renders as a table
  of zero rows, which is exactly how an empty store renders. `inspectorModel`
  is the odd one out and `throws` (`:24`), and its doc comment states the
  principle the siblings break: "Fetch failures still throw so a destructive
  caller cannot confuse an unavailable row with an unavailable store"
  (`:17-19`). That matters most here because Inspector's whole job is deciding
  whether state is worth erasing, and it is the runtime the app boots into
  *because* a store may be unreadable. Either propagate the throw to callers
  that can render a failure, or log a warning before degrading. (audit 2026-08-16)

## Completed issues

- test: Split the inherited SwiftData browsing test monolith by entity,
  reflection, row rendering, pagination, relationship, and mutation concerns.
  (agent 2026-07-30)
