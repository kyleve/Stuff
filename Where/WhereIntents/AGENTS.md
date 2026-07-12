# WhereIntents – Module Shape

WhereIntents is the App Intents layer of the Where feature: the query + action
intents (and their interactive snippet cards) that expose Where to Siri,
Spotlight, and the Shortcuts app. See [`README.md`](README.md) for the intent
list and data paths.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md) — read those first (they own build/format,
layering, localization, and the WhereUI duplicate-metadata rule).

## Scope & dependencies

- **App Intents + SwiftUI + `WhereCore` + `WhereUI`** (plus `RegionKit`,
  `LogKit`). Library target in [`Package.swift`](../../Package.swift)
  (`Where/WhereIntents/Sources`), linked by the **Where** app. It depends on
  **WhereUI** for its snippet cards — mirroring **WhereWidgets** — so it must
  **not** link `BroadwayUI`/`BroadwayCore` directly (a second copy would split
  Broadway's type-keyed metadata; see the root AGENTS "Targets" note).
- Intents stay **thin adapters**: they resolve `WhereServices.forIntents()` and
  delegate to its collaborators. Domain rules, persistence, and aggregation stay
  in `WhereCore`; presentation (the card bodies) stays in `WhereUI`. Don't
  reimplement any of that here.

## Invariants

- **The `AppShortcutsProvider` lives in the Where app target**
  (`Where/Where/Sources/WhereShortcuts.swift`), not here, so App Intents
  metadata extraction reliably discovers the phrases. Intent/entity/enum types
  are `public` so it can reference them.
- **Intents never start GPS.** `WhereServices.forIntents()` wires
  `IdleLocationSource`; a manual entry logged from an intent records a
  `ManualEntryAudit` with a "Logged with Siri" note and no captured location.
- **Reads open the shared App Group store** (`.localOnly`, matching the share
  extension); the running app observes the write via `.NSPersistentStoreRemoteChange`.
- **Snippet `perform()` is side-effect-free and re-run on reload.** The
  interactive `DaysInRegionSnippetIntent.perform()` only re-reads and re-renders;
  its `Button(intent:)` runs a separate action intent (`LogDayIntent`) that
  mutates, then the snippet reloads. Never mutate inside a `SnippetIntent`.
- **`Region` mapping is centralized** on `RegionAppEnum`/`RegionEntity`
  (`rawValue`-keyed); display names come from `Region.localizedName`, never a
  duplicated catalog entry.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereIntentsTests`, hosted in
`StuffTestHost`). Drive intent read/write logic against
`PreviewSupport.previewServices()` (in-memory, no-op schedulers) seeded via
`DayJournal` — never the on-disk store. Follows the WhereUITests dependency
shape (no `extraPackageProducts`; everything arrives transitively through
WhereUI). Internal types are reached via `@testable import WhereIntents`.
