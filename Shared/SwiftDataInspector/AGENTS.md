# SwiftDataInspector – Module Shape

SwiftDataInspector is an app-agnostic, **read-only** SwiftData browser: hand it
a `ModelContainer` (via `SwiftDataInspectorConfiguration`) and
`SwiftDataInspectorView` lists every entity, drills into a paged table of rows,
and resolves relationships on demand — generically, with no per-app model code.
See [`README.md`](README.md) for the full narrative and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **SwiftUI + SwiftData + Foundation + Observation** (UIKit only for font
  metrics). It must **not** import WhereCore or any app code — app wiring
  comes in via the configuration.
- Only `SwiftDataInspectorConfiguration` and `SwiftDataInspectorView` are
  `public`; everything else is internal. The root view expects an ambient
  `NavigationStack` the consumer owns.
- **Intended for DEBUG / developer surfaces** — it uses contained private-API
  reflection and shows raw stored data, so consumers gate it behind
  `#if DEBUG`. Strings are plain literals (no localization catalog).
- Read-only: every read uses a fresh throwaway `ModelContext`; never insert,
  update, delete, or save.

## Invariants

- **All private-API reflection stays in
  [`SwiftDataReflection.swift`](Sources/SwiftDataReflection.swift).** SwiftData
  has no public API for "fetch by metatype" or "read an attribute by name", so
  that one file isolates the reflection, and every helper degrades gracefully
  (`nil` / `[:]` / `.none`) so a SwiftData update shows blank cells, not a
  crash. Prefer public `Schema` API when one exists.
- **The table never faults in blobs or relationship graphs to draw a row** —
  binary and relationship columns render placeholders. Relationships are
  faulted only on an explicit detail drill-in, capped to `rowLimit`, in one
  batch fetch.
- **"Load more" grows a single-fetch prefix** (re-fetch a longer prefix and
  replace) rather than appending offset pages — `FetchDescriptor` has no sort
  to make an offset boundary stable.
- **Navigation composes with the host stack — no value-based links.** Every
  drill-in is a closure `NavigationLink` or `navigationDestination(item:)`;
  value-based routing in the consumer's stack double-pushes. Don't switch.
- **All store work stays on the `SwiftDataInspectorReader` actor** — the main
  actor only renders `Sendable` snapshots; the `ModelContext` never escapes.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`: build an
in-memory `ModelContainer` with local `@Model` fixtures, drive
`SwiftDataInspectorModel`, and assert on the returned snapshots. Real-app
wiring is covered from the consumer side (`WhereUITests`).

How it renders is pinned by the image snapshots in
[`SnapshotTests/`](SnapshotTests) — the module's own
`SwiftDataInspectorSnapshotTests` bundle, wired per the root
[`AGENTS.md`](../../AGENTS.md#targets); it links only `SwiftDataInspector`,
so nothing here builds against an app module. Snapshot the module the way a
consumer gets it — a **local fixture schema**, never a host app's store, no
design-system root — and prefer adding a case there over a hosted "renders
without crashing" test. Keep fixture `@Model` names distinct from the ones in
[`Tests/`](Tests): the bundles can't collide today (each `.xctest` gets its
own host process), but identical class names would clash in the ObjC runtime
if a toolchain ever co-loaded them.
