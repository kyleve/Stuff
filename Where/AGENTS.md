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
  WhereCore/     SPM library – domain model, persistence, GPS, aggregation
  WhereUI/       SPM library – SwiftUI views + view models (depends on WhereCore)
  WhereTesting/  SPM library – iOS test host helpers (show(), waitFor, ...)
  WhereWidgets/  Widget extension – reads published snapshots, renders WhereUI views
  RegionViewer/  Mac Catalyst shell for the region-map developer tool
```

- **App target** `Where` is intentionally tiny: it wires `RootView` from
  `WhereUI` into a `WindowGroup`. Add domain behavior to `WhereCore`,
  presentation and view-model wiring to `WhereUI`.
- **`WhereCore`** is the domain layer: pure Swift + Foundation + SwiftData +
  CoreLocation; it must **not** import SwiftUI or UIKit. Bundled region
  polygons (`Resources/*.geojson`) ship here.
- **`WhereUI`** is the SwiftUI layer: views plus `@Observable` view models
  (`WhereModel` app-level, `WhereSession` logged-in over `WhereServices`). It
  is **not** the domain model — see [Layering](#layering).

## Layering

Where splits **domain** from **presentation**. Keep the split sharp — views
must not grow business logic just because SwiftUI makes it easy.

| Layer | Where | Owns |
|-------|-------|------|
| **Domain / services** | `WhereCore` (`WhereServices` collaborators) | Rules, detection, aggregation, persistence, side effects (reminders, widgets, backup). Unit-test here. |
| **View model** | `WhereUI` (`WhereSession`, `WhereModel`) | Lifecycle wiring, observable mirrors of service output, UI intent methods. Orchestrates `WhereServices`; does not reimplement Core rules. |
| **Views** | `WhereUI` (`*View`) | Layout, navigation, localized copy, bindings to session/model. Calls view-model methods; does not talk to the store, run detection, or own cache/throttle policy. |

When in doubt: if the behavior would still be correct without SwiftUI, it
belongs in `WhereCore` (or, for logged-in orchestration that exists only to
serve the UI, on `WhereSession` — still not in a `View`).

Rules the code enforces and agents must preserve:

- **`WhereServices` is the entry point** to the domain — UI never talks to the
  store or location source directly.
- **All store mutations happen inside `WhereStore.perform { ... }`** (the block
  owns the write transaction; the production store traps otherwise). Values
  cross the persistence boundary, never SwiftData records.
- **One read path.** Every committed write (manual edit, live GPS, CloudKit
  remote import) pings the single store-change signal (`WhereStore.changes()`),
  and readers refresh purely off it — write intents just commit, they don't
  refresh inline. Launch is driven by
  [`LifecycleKit`](../Shared/LifecycleKit) (see `WhereLaunch` in WhereUI).
- **All logging goes through `WhereLog.channel(_:)`** with a typed
  `WhereLog.Category` case, never a raw string. Messages log as `.public`, so
  keep PII out. `info` = success of an important operation, `warning` =
  degraded-but-handled, `error`/`fault` = outright failure; hot paths
  (per-sample persist, widget throttle) stay quiet by design.
- **Location comes through the `LocationSource` protocol** — production is
  `CoreLocationSource`; tests and previews use `ScriptedLocationSource`.

## Localization

All user-facing copy resolves through module string catalogs — no literals in
views or thrown errors.

- **WhereUI:** funnel every string through `Strings.swift` (keys in the module
  `Localizable.xcstrings`, `bundle: .module`). Counts use catalog plural
  variations; years use a grouping-free number style ("2026", not "2,026").
- **WhereCore:** user-visible errors and region names use static
  `String(localized:bundle: .module)` keys in its own catalog.
- **DEBUG-only UI** still gets catalog entries — don't bypass localization
  because a surface is dev-only.
- **WhereWidgets:** gallery name/description live in the extension's own
  catalog; in-widget copy reuses WhereUI `Strings`.

Add the key to the catalog first, then reference it — never ship English
literals in SwiftUI `Text` or `errorDescription`.

## Dates & presentation

- **Year bounds are half-open** (`[Jan 1 year, Jan 1 year+1)`); **day ranges
  are inclusive** (`Date.calendarDays(through:in:)`).
- **Inject `Calendar`, don't reach for globals** — logged-in UI reads
  `WhereSession.calendar`; layout types carry the calendar they were built
  with. Prefer calendar APIs over hardcoding day/weekday counts.
- **Core layout APIs throw on failure**; views surface
  `ContentUnavailableView` + log, never `!`.
- Layout constants live in `UIConstants`, shared date-range copy in
  `DateRangeFormatting`; numbers and dates use `FormatStyle`, not string
  interpolation. Expensive layout computes once into state, not per `body`
  pass. Sharing uses `ShareLink` / `Transferable`.

## SwiftUI views & previews

Every previewable component in `WhereUI` (any `View`, `Widget`, or
`WidgetBundle`) **must** ship at least one `#Preview` in the same file,
wrapped in `#if DEBUG` at the bottom. Don't construct services, stores, or
location sources inline — pull fixtures from
[`PreviewSupport`](WhereUI/Sources/Preview/PreviewSupport.swift) (synchronous,
in-memory, never touch disk/CloudKit/CoreLocation) and inject what the view
reads from the environment (`WhereSession` for logged-in views, `WhereModel`
for the app shell). Cover the states that matter — empty, loaded, and distinct
edge states — not just the happy path.

## Adding things

- **New library target:** add to root [`Package.swift`](../Package.swift)
  under `Where/<Name>/Sources`, then wire a hosted test bundle in
  [`Project.swift`](../Project.swift) via the `unitTests` helper.
- **New region:** add the `Region` case, then resolve the two compile errors
  it forces: a `localizedName` catalog entry and a `Region.geometrySource`
  case (`.usStateFeature(name:)` or `.bundledFile` with a new
  `<rawValue>.geojson` in WhereCore's `Resources/`). Add a
  `RegionAttributorTests` spot-check.
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
