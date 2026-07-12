# Where – Feature Shape

Where is an iOS/iPadOS/macOS app for answering "what region was I in on which
day?" It ingests passive GPS (Visits + significant-change), accepts
user-asserted history (manual coordinates, whole-day overlays, evidence like
boarding passes), and rolls everything up into per-day region presence and
per-year reports. The primary use case is residency / day-count audits, so a
day "counts" for a region if **any** sample in that calendar day fell inside
the region's polygon (a single day can belong to multiple regions, e.g. a
CA→NY same-day flight).

This file complements the root [`AGENTS.md`](../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Modules

```
Where/
  Where/         App target – SwiftUI entry point (WhereApp → RootView)
  RegionKit/     SPM library – geometry, GeoJSON, Region model + lookup (WhereCore depends on it)
  WhereCore/     SPM library – domain model, persistence, GPS, aggregation
  WhereUI/       SPM library – SwiftUI views + view models (depends on WhereCore)
  WhereTesting/  SPM library – iOS test host helpers (show(), waitFor, ...)
  WhereWidgets/  Widget extension – reads published snapshots, renders WhereUI views
  WhereShareExtension/  Share extension – saves shared content as Evidence into the App Group store
  RegionViewer/  Mac Catalyst shell for the region-map developer tool
```

- **App target** `Where` is intentionally tiny: it wires `RootView` from
  `WhereUI` into a `WindowGroup`. Add domain behavior to `WhereCore`,
  presentation and view-model wiring to `WhereUI`.
- **`RegionKit`** is the lowest layer: the `Region` model, coordinate geometry
  (`Coordinate`, `GeoPolygon`, `BoundingBox`, `LongitudeSpan`), GeoJSON
  decoding, and coordinate-to-`Region` lookup (`RegionAttributor`). Pure Swift +
  Foundation + LogKit; the bundled region polygons (`Resources/*.geojson`) and
  the region-name catalog ship here. See [`RegionKit/AGENTS.md`](RegionKit/AGENTS.md).
- **`WhereCore`** is the domain layer: pure Swift + Foundation + SwiftData +
  CoreLocation; it must **not** import SwiftUI or UIKit. It depends on
  **`RegionKit`** and calls into it for region lookup.
- **`WhereUI`** is the SwiftUI layer: views plus `@Observable` view models —
  the app-level `WhereModel`, the always-on `WhereSession` coordinator (no
  presentation state), and its scope-tiered children (scene-scoped
  `YearReportModel`, view-scoped `ResolveModel` / `BackupModel` /
  `RemindersSettingsModel`). It is **not** the domain model — see
  [Layering](#layering).
- **Developer tools** live behind a DEBUG-only floating overlay, not in Settings.
  `Developer/DeveloperOverlay` is attached once at `RootView` (above every launch
  phase and tab, reachable even logged out): a draggable, corner-snapping
  `DeveloperOverlayButton` that expands into a Picture-in-Picture panel and grows
  to full screen, hosting `Developer/DeveloperToolsView` (Logs / SwiftData
  inspector / region map). All of it is compiled out of release.

## Layering

Where splits **domain** from **presentation**. Keep the split sharp — views
must not grow business logic just because SwiftUI makes it easy.

| Layer | Where | Owns |
|-------|-------|------|
| **Domain / services** | `WhereCore` (`WhereServices` collaborators) | Rules, detection, aggregation, persistence, side effects (reminders, widgets, backup). Unit-test here. |
| **View model** | `WhereUI` (`WhereModel`, the `WhereSession` coordinator + scope-tiered `YearReportModel` / `ResolveModel` / `BackupModel` / `RemindersSettingsModel`) | Lifecycle wiring, observable mirrors of service output, UI intent methods. Orchestrates `WhereServices`; does not reimplement Core rules. |
| **Views** | `WhereUI` (`*View`) | Layout, navigation, localized copy, bindings to the coordinator / scoped models. Calls view-model methods; does not talk to the store, run detection, or own cache/throttle policy. |

When in doubt: if the behavior would still be correct without SwiftUI, it
belongs in `WhereCore` (or, for orchestration that exists only to serve the
UI, on the `WhereSession` coordinator or a scoped model — still not in a
`View`).

Rules the code enforces and agents must preserve:

- **`WhereServices` is the entry point** to the domain — UI never talks to the
  store or location source directly.
- **All store mutations happen inside `WhereStore.perform { ... }`** (the block
  owns the write transaction; the production store traps otherwise). Values
  cross the persistence boundary, never SwiftData records.
- **One read path.** Every committed write (manual edit, live GPS, CloudKit
  remote import) pings the single store-change signal (`WhereStore.changes()`),
  and readers refresh purely off it — write intents just commit, they don't
  refresh inline. The scene's `YearReportModel` subscribes while it's active;
  `DataIssueScanner` drops its cache on the same signal. Launch is driven by
  [`LifecycleKit`](../Shared/LifecycleKit) (see `WhereLaunch` in WhereUI).
- **All logging goes through `WhereLog.channel(_:)`** with a typed
  `WhereLog.Category` case, never a raw string. Messages log as `.public`, so
  keep PII out. `info` = success of an important operation, `warning` =
  degraded-but-handled, `error`/`fault` = outright failure; hot paths
  (per-sample persist, widget throttle) stay quiet by design. **RegionKit** logs
  through its own `RegionLog` facade (subsystem `com.stuff.regionkit`, separate
  store) since it can't see `WhereLog`; the DEBUG developer log viewer is
  configured with **both** buffers (`[WhereLog.store, RegionLog.store]`) so it
  shows a single merged stream.
- **Location comes through the `LocationSource` protocol** — production is
  `CoreLocationSource`; tests and previews use `ScriptedLocationSource`. Besides
  the passive `sampleStream`, it offers a best-effort one-shot
  `requestCurrentLocation()` (re-exposed as `LocationIngestor.currentLocation()`)
  used to stamp manual entries; it returns `nil` rather than throwing when no
  fix is available.
- **Manual entries carry a `ManualEntryAudit`** (when made, an optional note,
  and a best-effort capture-time `CapturedLocation`). The view-model intents
  (`YearReportModel.setManualDay` / `setManualDays` / `overrideDay`) assemble it
  from a `note:` plus `currentLocation()`; `DayJournal`'s write methods take an
  explicit `audit:` (no default) and persist it on `DayPresence` /
  `SDManualDay`. An additive backfill can't downgrade an authoritative row's
  regions, but the newer audit always wins. `DayRelabelView` shows it read-only.
- **`WhereServices.recentActivity`** is a standalone, on-demand
  `RecentActivitySummarizer` that summarizes a selectable look-back window
  (`RecentActivityWindow`: 24h / week / month / year-so-far) of locations on
  device via Foundation Models (behind the `ActivitySummaryGenerating` seam). It
  collapses consecutive same-region readings into transitions and caps them so a
  long window's prompt still fits the model's context. It is distinct from
  `WhereServices.summary` (the daily notification recap); model unavailability
  surfaces as a typed reason, never a silent empty summary. The sheet
  (`RecentActivitySummaryView`) streams the result in with a typewriter reveal
  (`TypewriterText`) and shows `AppIconActivityIndicator` — a subtle cousin of
  the launch splash's pulsing icon — while generating.

## Localization

All user-facing copy resolves through module string catalogs — no literals in
views or thrown errors.

- **WhereUI:** funnel every string through `Strings.swift` (keys in the module
  `Localizable.xcstrings`, `bundle: .module`). Counts use catalog plural
  variations; years use a grouping-free number style ("2026", not "2,026").
- **WhereCore:** user-visible errors use static
  `String(localized:bundle: .module)` keys in its own catalog.
- **RegionKit:** region names (`Region.localizedName`) use static
  `String(localized:bundle: .module)` keys in RegionKit's own catalog.
- **DEBUG-only UI** still gets catalog entries — don't bypass localization
  because a surface is dev-only.
- **WhereWidgets:** gallery name/description live in the extension's own
  catalog; in-widget copy reuses WhereUI `Strings`.
- **WhereShareExtension:** compose-sheet chrome lives in the extension's own
  catalog (`ShareStrings`); evidence kind names reuse WhereUI's public
  `EvidenceKind` presentation helpers.

Add the key to the catalog first, then reference it — never ship English
literals in SwiftUI `Text` or `errorDescription`.

## Dates & presentation

- **Year bounds are half-open** (`[Jan 1 year, Jan 1 year+1)`); **day ranges
  are inclusive** (`Date.calendarDays(through:in:)`).
- **Inject `Calendar`, don't reach for globals** — the scene's
  `YearReportModel` owns the calendar (Gregorian, current time zone) its
  missing-day math uses; layout types carry the calendar they were built with.
  Prefer calendar APIs over hardcoding day/weekday counts (`Calendar.dayCount`
  derives 365/366 rather than assuming a length).
- **Core layout APIs throw on failure**; views surface
  `ContentUnavailableView` + log, never `!`.
- Layout tokens live in `WhereStylesheet` (a Broadway `BStylesheet`, read in
  views via `@Environment(\.stylesheet)`; off the `View` tree — layout helpers,
  tests — use `WhereStylesheet.default`). `RootView` seeds the Broadway context
  with `.broadwayRoot(themes: WhereThemes.current)`, so tokens can derive from
  live traits (e.g. bigger day-grid tap targets at accessibility Dynamic Type
  sizes, a flatter card under Reduce Transparency). Shared date-range copy lives
  in `DateRangeFormatting`; numbers and dates use `FormatStyle`, not string
  interpolation. Expensive layout computes once into state, not per `body`
  pass. Sharing uses `ShareLink` / `Transferable`.

## SwiftUI views & previews

Every previewable component in `WhereUI` (any `View`, `Widget`, or
`WidgetBundle`) **must** ship at least one `#Preview` in the same file,
wrapped in `#if DEBUG` at the bottom. Don't construct services, stores, or
location sources inline — pull fixtures from
[`PreviewSupport`](WhereUI/Sources/Preview/PreviewSupport.swift) (synchronous,
in-memory, never touch disk/CloudKit/CoreLocation). Pass scoped models
explicitly (a `YearReportModel` via `report:`, a seeded `ResolveModel`) and
inject ambient app state through the environment (`WhereModel` for the app
shell, the `WhereSession` coordinator for logged-in views). Cover the states
that matter — empty, loaded, and distinct edge states — not just the happy
path.

Animate transitions between distinct states in a way that fits the surface and
its content — don't hard-cut. A view that swaps on a `LoadState` (or shows an
in-flight status) should fade/move rather than snap (e.g. `.transition(.opacity)`
on each `switch` arm plus `.animation(_:value:)`, or `.animation(_:value:)` on a
form that reveals a saving row). See `RecentActivitySummaryView` and the
manual-entry forms.

## Adding things

- **New library target:** add to root [`Package.swift`](../Package.swift)
  under `Where/<Name>/Sources`, then wire a hosted test bundle in
  [`Project.swift`](../Project.swift) via the `unitTests` helper.
- **New region:** add the `Region` case in **`RegionKit`**, then resolve the two
  compile errors it forces: a `region.<rawValue>` entry in RegionKit's
  `Resources/Localizable.xcstrings` (for `localizedName`) and a
  `Region.geometrySource` case (`.usStateFeature(name:)` or `.bundledFile` with a
  new `<rawValue>.geojson` in RegionKit's `Resources/`). Add a
  `RegionAttributorTests` spot-check (in `RegionKit/Tests`).
- **New evidence kind / sample source:** add the case and follow the compile
  errors through the exhaustive switches.
- **New app icon:** run `./icons --add` (see the root
  [`AGENTS.md`](../AGENTS.md#managing-app-icons)) — never hand-edit the
  catalogs or manifest.

## Testing

- Test bundles run in `StuffTestHost` via the `unitTests` helper in
  `Project.swift` and link `WhereTesting` (`show(_:perform:)`, `waitFor`).
- Use `ScriptedLocationSource` and `SwiftDataStore.inMemory()` — never
  `CoreLocationSource` or the user's on-disk/CloudKit store. The CloudKit
  remote-import path is exercised with the `@_spi(Testing)`
  `inMemory(remoteChangeSource:)` + `ScriptedStoreRemoteChangeSource`.
- Root rules apply: 1:1 test files, shared fixtures in `*TestSupport.swift`,
  wait for conditions rather than fixed delays, inject small limits via
  `@_spi(Testing)`.
