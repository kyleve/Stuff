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

Each module's own `AGENTS.md` / `README.md` is the authority on what it is.
The layering stack, bottom-up: **RegionKit** (geometry + region lookup) →
**WhereCore** (domain; never imports SwiftUI/UIKit) → **WhereUI** (SwiftUI
views + view models — *not* the domain model) → the thin hosts (**Where** app,
**WhereIntents**, **WhereWidgets**, **WhereShareExtension**, **RegionViewer**).
Each layer reaches only *down*. The app target stays intentionally tiny: add
domain behavior to WhereCore, presentation to WhereUI — not there.

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
- **All logging goes through [Periscope](../Shared/Periscope)** via the
  `WhereLog` facade — a `"Where"` root `Log` scope with grouping scopes
  (`location`, `reminders`, `backup`, `widgets`, `session`, `evidence`,
  `recentActivity`) that each collaborator derives a typed `LogEvent` leaf from
  (`WhereLog.<group>(SomeLog.self)` / `WhereLog.root(SomeLog.self)`), never a
  raw string. Each module keeps its facade and `*Log.swift` event types together
  in its own `Sources/Logging/` folder. Events log as `.public`, so keep PII out; catch-path events carry
  a `LogAttachment.error(_:)`. `info` = success of an important operation,
  `warning` = degraded-but-handled, `error`/`fault` = outright failure; hot
  paths (per-sample persist, widget throttle) stay quiet by design. **RegionKit**
  emits through its own `RegionLog` facade (a separate `"RegionKit"` root scope)
  since it can't see `WhereLog`, but into the *same* process-wide
  `Periscope.shared` — the app attaches one `PeriscopeStore` sink at launch, and
  the DEBUG developer surface (`PeriscopeViewer`) shows every scope subtree in a
  single stream. Widgets, the share extension, and the intents surface run in
  their own processes, so their `Periscope.shared` stays OSLog-only (no store).
  An event that concerns a store object stamps its `externalID` with the
  object's canonical `store://` identity — `DataIssueID.storeURL` for dismissals,
  and `WhereStoreID` (`store://days/…`, `store://years/…`, `store://evidence/…`,
  `store://samples/…`) for the other families — so inspect-by-object shares the
  same key the store and backups use. **RegionKit** can't see the app's
  `store://` types, so it owns a parallel `region://` scheme (`RegionURL`,
  `Region.regionURL` → `region://regions/<id>`) and `RegionAttributorLog` keys on
  that — a separate namespace, since regions are a bundled catalog, not store rows.
- **Location comes through the `LocationSource` protocol** — production is
  `CoreLocationSource`; tests and previews use `ScriptedLocationSource`. Besides
  the passive `sampleStream`, it offers a best-effort one-shot
  `requestCurrentLocation()` — used both to stamp manual entries and to log
  today when the app is opened on a day with no GPS sample yet
  (`LocationIngestor.captureTodayIfNeeded`, driven by `WhereSession` on launch/
  foreground); it returns `nil` rather than throwing when no fix is available.
- **Manual entries carry a `ManualEntryAudit`** (when made, an optional note,
  and a best-effort capture-time `CapturedLocation`). The view-model intents
  assemble it; `DayJournal`'s write methods take an explicit `audit:` (no
  default) and persist it. An additive backfill can't downgrade an
  authoritative row's regions, but the newer audit always wins.
- **`WhereServices.recentActivity`** (the on-demand Foundation Models
  activity summarizer, behind the `ActivitySummaryGenerating` seam) is
  distinct from `WhereServices.summary` (the daily notification recap). It
  caps collapsed region transitions so a long window's prompt still fits the
  model's context, and model unavailability surfaces as a typed reason — never
  a silent empty summary.

## Localization

All user-facing copy resolves through module string catalogs — no literals in
views or thrown errors.

- **WhereUI:** funnel every string through `Strings.swift` (keys in the module
  `Localizable.xcstrings`, `bundle: .module`). Counts use catalog plural
  variations; years use a grouping-free number style ("2026", not "2,026").
- **WhereCore:** user-visible errors use static
  `String(localized:bundle: .module)` keys in its own catalog.
- **RegionKit:** region names (`Region.localizedName`) come from the
  `regions.json` manifest, with an optional `localizationKey` overriding from
  RegionKit's own `Localizable.xcstrings` (`bundle: .module`) — so, unlike the
  other modules, region names lose static string-catalog extraction (a
  deliberate trade-off for a data-driven catalog).
- **Extensions** (WhereWidgets, WhereShareExtension) keep their chrome in
  their own catalogs and reuse WhereUI's public presentation helpers for
  shared copy.
- **DEBUG-only UI** still gets catalog entries — don't bypass localization
  because a surface is dev-only.

Add the key to the catalog first, then reference it — never ship English
literals in SwiftUI `Text` or `errorDescription`.

## Dates & presentation

- **A logical day is a `CalendarDay` (Y-M-D), not a `Date`.** It is the
  timezone-independent identity every stored day-record and day comparison keys
  on (see [`WhereCore/AGENTS.md`](WhereCore/AGENTS.md)); a `Date` is only for
  instants (GPS bucketing, grid geometry, display), derived via
  `CalendarDay.startOfDay(in:)`. Never persist a day as an absolute instant.
- **Year bounds are half-open** (`[Jan 1 year, Jan 1 year+1)`); **day ranges
  are inclusive** (`Date.calendarDays(through:in:)` for instants,
  `CalendarDay.days(through:)` for logical days).
- **The app is Gregorian-only.** All presence data is aggregated in a Gregorian
  calendar (`DayAggregator()` defaults to Gregorian + current time zone), so any
  day/year math must use a Gregorian calendar — **never `Calendar.current`**,
  which on a non-Gregorian device (Buddhist, Japanese-era, …) reports a
  different year and silently mismatches the stored reports. Use the calendar
  the owning type vends (below), or a fresh `Calendar(identifier: .gregorian)`
  with the current time zone (see `Calendar.whereIntents` in WhereIntents).
- **Inject `Calendar`, don't reach for globals** — the scene's
  `YearReportModel` owns the calendar (Gregorian, current time zone) its
  missing-day math uses; layout types carry the calendar they were built with.
  Prefer calendar APIs over hardcoding day/weekday counts (`Calendar.dayCount`
  derives 365/366 rather than assuming a length).
- **Core layout APIs throw on failure**; views surface
  `ContentUnavailableView` + log, never `!`.
- Appearance tokens live in `WhereStylesheet` — see
  [`WhereUI/AGENTS.md`](WhereUI/AGENTS.md) for how to read and extend it.
  Shared date-range copy lives in `DateRangeFormatting`; numbers and dates use
  `FormatStyle`, not string interpolation. Expensive layout computes once into
  state, not per `body` pass. Sharing uses `ShareLink` / `Transferable`.

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

- **Animate transitions between distinct states** in a way that fits the
  surface and its content — don't hard-cut. A view that swaps on a `LoadState`
  (or shows an in-flight status) should fade/move rather than snap (e.g.
  `.transition(.opacity)` on each `switch` arm plus `.animation(_:value:)`).
  Hidden means *out of the tree* (`if` + transition), not opacity zero.
- **Derive UI dimensions; don't repeat them.** A repeated dimension gets one
  named home; real chrome is measured from the live UI via a preference key /
  `onGeometryChange` (see `DeveloperTabBarInset`) rather than hardcoding its
  expected size; controls scale with `@ScaledMetric`; prefer semantic font
  styles over fixed point sizes.
- **Custom full-screen surfaces must work under VoiceOver.** A surface that
  takes over the screen carries the `.isModal` accessibility trait and posts
  `.screenChanged` when crossing the modal boundary (`.layoutChanged` for
  lighter transitions). Non-modal floating chrome stays reachable behind (see
  `DeveloperOverlay`).

## Adding things

- **New library target:** add to root [`Package.swift`](../Package.swift)
  under `Where/<Name>/Sources`, then wire a hosted test bundle in
  [`Project.swift`](../Project.swift) via the `unitTests` helper.
- **New region:** it's **pure data** now — add geometry under
  `RegionKit/Tools/source/`, run `ruby Where/RegionKit/Tools/generate-regions.rb`
  to regenerate `Resources/regions/` + `regions.json` (extend the script's id
  map / `NON_US` list as needed), optionally add a `region.<key>` string +
  `localizationKey`, and add a `RegionAttributorTests` spot-check. No `Region`
  case, no code — `RegionStyle`, region pickers, and the App Intents
  `RegionEntity` all derive from the catalog. (See
  [`RegionKit/README.md`](RegionKit/README.md#adding-a-region).)
- **New evidence kind / sample source:** add the case and follow the compile
  errors through the exhaustive switches.
- **New app icon:** run `./icons --add` (see the root
  [`AGENTS.md`](../AGENTS.md#managing-app-icons)) — never hand-edit the
  catalogs or manifest.

## Installing to a device

`./Where/install` builds the app and installs it on a connected iPhone
straight from the CLI — no Xcode UI. It regenerates the project, builds +
code-signs the `Where` scheme with `xcodebuild` (the Debug configuration with
compiler optimizations forced on by default, so the DEBUG-only developer
surfaces survive while the app still runs at roughly Release speed;
`-allowProvisioningUpdates` so the app + extensions provision automatically),
then copies and launches it via `xcrun devicectl` (see `./Where/install
--help`). macOS-only, and it needs a signing team configured once via `./ide
--team-id <ABCDE12345>`. Auto-picks the sole paired physical iPhone (booted
simulators are ignored) and prompts you to unlock it before installing; pass
`--configuration <name>` to build a different configuration (e.g. `Release`),
`--no-optimize` to leave the configuration's own optimization level alone,
`--device <name|udid>` to disambiguate, `--no-launch` to install without
launching, `--no-wait` (alias `-f`) to skip the unlock prompt without waiting
for you to unlock the device first.

## Testing

- Test bundles run in `StuffTestHost` via the `unitTests` helper in
  `Project.swift` and link `TestHostSupport` (`show(_:perform:)`, `waitFor`).
  The `InMemoryKeyValueStore` test double lives in `WhereCore` behind
  `@_spi(Testing)` (`#if DEBUG`) — import it with `@_spi(Testing) import WhereCore`.
- Use `ScriptedLocationSource` and `SwiftDataStore.inMemory()` — never
  `CoreLocationSource` or the user's on-disk/CloudKit store. The CloudKit
  remote-import path is exercised with the `@_spi(Testing)`
  `inMemory(remoteChangeSource:)` + `ScriptedStoreRemoteChangeSource`.
- Root rules apply: 1:1 test files, shared fixtures in `*TestSupport.swift`,
  wait for conditions rather than fixed delays, inject small limits via
  `@_spi(Testing)`.
