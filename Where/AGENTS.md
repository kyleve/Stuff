# Where – Feature Shape

Where is an iOS/iPadOS app for answering "what region was I in on which
day?" It ingests passive GPS (Visits + significant-change), accepts
user-asserted history (manual coordinates, whole-day overlays, evidence like
boarding passes), and rolls everything up into per-day region presence and
per-year reports. A day "counts" for a region if **any** sample in that
calendar day fell inside the region's polygon, so a single day can belong to
multiple regions.

This file complements the root [`AGENTS.md`](../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Modules

The layering stack, bottom-up: **RegionKit** (geometry + region lookup) →
**WhereCore** (domain; never imports SwiftUI/UIKit) → **WhereUI** (SwiftUI
views + view models) → the thin hosts (**Where** app, **WhereIntents**,
**WhereWidgets**, **WhereShareExtension**, **RegionViewer**). Each layer
reaches only *down*; each module's own `AGENTS.md` / `README.md` is the
authority on what it is. Add domain behavior to WhereCore and presentation to
WhereUI — the app target stays tiny.

## Layering

| Layer | Where | Owns |
|-------|-------|------|
| **Domain / services** | `WhereCore` (`WhereServices` collaborators) | Rules, detection, aggregation, persistence, side effects. Unit-test here. |
| **View model** | `WhereUI` (`WhereModel`, the `WhereSession` coordinator, the scoped `YearReportModel` / `ResolveModel` / `BackupModel` / `RemindersSettingsModel`) | Lifecycle wiring, observable mirrors of service output, UI intent methods. |
| **Views** | `WhereUI` (`*View`) | Layout, navigation, localized copy, bindings. Never store I/O, detection, or cache/throttle policy. |

When in doubt: if the behavior would still be correct without SwiftUI, it
belongs in `WhereCore` (or on the coordinator / a scoped model — still not a
`View`).

Rules the code enforces and agents must preserve:

- **`WhereServices` is the domain entry point** — UI never talks to the store
  or location source directly.
- **All store mutations run inside `WhereStore.perform { … }`** (the
  production store traps otherwise); values cross the boundary, never
  SwiftData records.
- **One read path.** Every committed write pings `WhereStore.changes()`, and
  readers refresh purely off that signal — write intents commit, they don't
  refresh inline. Launch is a typed [`LifecycleKit`](../Shared/LifecycleKit)
  `LaunchPlan` (`WhereLaunch` in WhereUI), rendered by
  [`LifecycleKitUI`](../Shared/LifecycleKitUI)'s container in `RootView`.
- **All logging goes through [Periscope](../Shared/Periscope)** as typed
  `LogEvent`s off the `WhereLog` facade, never a raw string; each module keeps
  its `*Log.swift` event types in its `Sources/Logging/` folder. Not
  re-derivable from source: events log `.public`, so **keep PII out**; `info`
  = important success, `warning` = degraded-but-handled, `error`/`fault` =
  outright failure; hot paths stay quiet by design. RegionKit emits a separate
  `"RegionKit"` root into the *same* `Periscope.shared`. Only the app process
  attaches a store — widgets and the share extension are OSLog-only; App
  Intents run in the app process. An event about a store object stamps its
  `externalID` with the object's `store://` identity; RegionKit's parallel
  scheme is `region://` (see [`RegionKit/AGENTS.md`](RegionKit/AGENTS.md)).
- **Location comes through the `LocationSource` protocol** —
  `CoreLocationSource` in production, `ScriptedLocationSource` in
  tests/previews. The one-shot `requestCurrentLocation()` returns `nil` rather
  than throwing when no fix is available.
- **Manual entries carry a `ManualEntryAudit`**; `DayJournal`'s write methods
  take an explicit `audit:` (no default). An additive backfill can't downgrade
  an authoritative row's regions, but the newer audit always wins.
- **`WhereServices.recentActivity`** (the on-demand Foundation Models
  summarizer, behind `ActivitySummaryGenerating`) is distinct from
  `WhereServices.summary` (the daily notification recap); model unavailability
  surfaces as a typed reason, never a silent empty summary.

## Scopes and the launch

- **A `WhereScope` is what the app is logged in *to*** — one open store's
  `WhereServices`, the `WherePreferences` driving it, and the durable log store
  they record into. Created whole; `WhereSession` is built from one, so a
  surface can't read one world's store against another's preferences.
- **Nothing opens until the user picks a world.** The trunk is rooted at the
  onboarding gate, so an install that never onboards creates no store file,
  contacts no CloudKit, and opens no log store. Guard:
  `WhereLaunchTests.firstRunForegroundLaunchParksOnTheOnboardingGateBeforeOpeningAnything`.
- **The store opens at most once per process.** Logging out — a reset, or
  leaving a demo — keeps the scope dormant, so logging back in reuses that
  container rather than racing a second one over the file. Guard:
  `WhereResetTests.loggingBackInAfterAResetReusesTheSameStore`.
- **The onboarding gate declares `modes: .all`,** not the `.foreground`
  default: parking a headless launch is the point. A background wake needs the
  permission this flow asks for, so `isNeeded` is false by then.
- **A gate carries no value,** so a choice made *at* it reaches `resolve-scope`
  through `WhereModel` — the one step that reads model state rather than the
  trunk.
- **Ambient log sources start at process launch; the durable sink is a
  scope's.** Records emitted before a scope exists reach OSLog only.

### Demo mode

- **Demo mode is a second scope, not a flag** — in-memory store seeded by
  `DemoDataBuilder`, in-memory preferences and log store, noop schedulers,
  outbox, and widget refresher. Entered from the onboarding intro, left from the
  first block of Settings (`WhereLaunch.exitDemoPlan`); quitting mid-demo needs
  no teardown.
- **A demo leaves no mark on the device.** Anything that writes outside its own
  store is injected as a no-op or skipped at the call site (Spotlight indexing
  in `AppDelegate`), and Settings hides the groups that would reach past it
  (`SettingsDestination.isAvailableInDemoMode`). A new persisting surface needs
  the same treatment.
- **`WhereModel` decides when a scope routes its logs.** A scope holds its log
  store from birth and routes only while active, so one that opens while
  shadowed is remembered rather than attached. Guard:
  `DemoModeTests.aLogStoreOpeningLateNeverAttachesToAShadowedScope`.
- **The logging system is injected, not global** — `WhereModel.logSystem` has no
  default, so a test can't silently attach sinks to `Periscope.shared`. (The
  `WhereLog` facade still emits into `.shared`; pre-existing.)
- **Demo mode asks for no permission and presents a granted user** — the
  scripted location source reports `.always`, and the noop schedulers are built
  `authorized: true` so no surface nags about a permission the demo can't
  obtain. Guard: `DemoModeTests.demoPresentsAFullyGrantedUser`.
- **Views branch on `\.isInDemoMode`,** seeded once at `RootView` via
  `demoMode(of:)`. Guard: `DemoModeEnvironmentTests`.
- App Intents answer from the demo store while it is active: process-scoped and
  self-correcting on exit, accepted rather than special-cased (#150).

## Navigation

The logged-in shell is `MainTabs` — **three fixed tabs**: Locations, Your
Year, Settings; everything else hangs off one of them. A new screen is a
pushed destination, a sheet, or a Settings row inside that shape — a fourth
tab is a product decision to raise before building. `MainTabs` passes the
scene-scoped `YearReportModel` by explicit init injection; the always-on
`WhereSession` coordinator travels in the environment. Settings is a
typed-route list (`SettingsSearch.swift`; every switch is exhaustive), so a
new drill-in is a set of compile errors to fill in; About stays the last
block and the demo-mode exit the first.

The About screen renders three live sources — the generated attribution
report (`WhereCore.AppAttribution`), `RegionDataSource`, and `BuildInfo` —
never a list hard-coded in the view. A missing report or unstamped build
renders an honest empty state, and shipped libraries stay a separate section
from development tools. Design and rationale: PR #140.

## Localization

All user-facing copy resolves through each module's `Localizable.xcstrings`
via Xcode's generated `LocalizedStringResource` symbols, so a typo'd or
removed key is a compile error. Add a key as a **manual** entry first (so its
symbol generates), then reference `.thatSymbol` — never a raw
`String(localized: "literal.key")`, a hand-maintained key facade, or an
English literal in `Text` / `errorDescription`.

- **WhereUI:** reference symbols directly; composition, pluralization, and
  number/coordinate formatting go through
  [`WhereFormat`](WhereUI/Sources/Shared/WhereFormat.swift).
- **RegionKit:** region names resolve dynamically from `regions.json`
  (+ optional `localizationKey`) — the one deliberate exception to static
  symbols (see [`RegionKit/AGENTS.md`](RegionKit/AGENTS.md)).
- **Extensions** use their own generated symbols for chrome and WhereUI's
  public helpers for shared copy. **DEBUG-only UI** is still localized.
- The catalogs carry a few value-less **auto-extracted** entries (`""`,
  `%lld`): Xcode's, not ours — an IDE build re-adds a deleted one, so remove
  the *source* literal instead. Catalogs stay byte-identical to Xcode's own
  serialization (root [Formatting](../AGENTS.md#formatting)).

## Dates & presentation

- **A logical day is a `CalendarDay` (Y-M-D), not a `Date`** — see
  [`WhereCore/AGENTS.md`](WhereCore/AGENTS.md). Never persist a day as an
  absolute instant.
- **Year bounds are half-open; day ranges are inclusive**
  (`Date.calendarDays(through:in:)`, `CalendarDay.days(through:)`).
- **The app is Gregorian-only: never `Calendar.current`** — a non-Gregorian
  device calendar silently mismatches the stored reports. Use the calendar the
  owning type vends, or a fresh `Calendar(identifier: .gregorian)` with the
  current time zone (see `Calendar.whereIntents`).
- **Inject `Calendar`, don't reach for globals**; prefer calendar APIs over
  hardcoded day/weekday counts (`Calendar.dayCount(ofYear:)`).
- **Core layout APIs throw on failure**; views surface
  `ContentUnavailableView` + log, never `!`.
- Appearance tokens live in `WhereStylesheet`
  ([`WhereUI/AGENTS.md`](WhereUI/AGENTS.md)); shared date-range copy in
  `DateRangeFormatting`; numbers and dates use `FormatStyle`, not string
  interpolation. Expensive layout computes once into state, not per `body`
  pass. Sharing uses `ShareLink` / `Transferable`.

## SwiftUI views & previews

Every previewable component in `WhereUI` (any `View`, `Widget`, or
`WidgetBundle`) **must** ship at least one `#Preview` in the same file,
wrapped in `#if DEBUG` at the bottom, built from
[`PreviewSupport`](WhereUI/Sources/Preview/PreviewSupport.swift) fixtures —
synchronous, in-memory, never disk/CloudKit/CoreLocation. Cover empty,
loaded, and distinct edge states, not just the happy path.

- **Animate transitions between distinct states** — `.transition` on each
  `switch` arm plus `.animation(_:value:)`; hidden means *out of the tree*,
  not opacity zero.
- **A displayed value that can change under the user morphs, too** — a
  `.contentTransition` needs a paired `.animation(_:value:)` or it silently
  hard-cuts, and the transition and its animation are one stylesheet token
  (see `CardStyles.DayCountStyle`).
- **Derive UI dimensions; don't repeat them** — measure real chrome via a
  preference key / `onGeometryChange` (see `DeveloperTabBarInset`), scale
  controls with `@ScaledMetric`, prefer semantic font styles.
- **Custom full-screen surfaces must work under VoiceOver** — the `.isModal`
  trait plus `.screenChanged` across the modal boundary (see
  `DeveloperOverlay`).

## Adding things

- **New library target:** root [`Package.swift`](../Package.swift) under
  `Where/<Name>/Sources`, plus a hosted test bundle via `Project.swift`'s
  `unitTests` helper.
- **New region:** pure data — no `Region` case, no code; see
  [`RegionKit/README.md`](RegionKit/README.md#adding-a-region).
- **New evidence kind / sample source:** add the case and follow the compile
  errors through the exhaustive switches.
- **New app icon:** `./icons --add` (root
  [`AGENTS.md`](../AGENTS.md#managing-app-icons)) — never hand-edit the
  catalogs or manifest.

## Installing to a device

`./Where/install` builds, signs, and installs the app onto a connected iPhone
from the CLI — macOS-only, one-time `./ide --team-id <id>` setup. It defaults
to Debug with compiler optimizations forced on, so DEBUG-only developer
surfaces survive at near-Release speed. Options: `./Where/install --help`.

## Testing

Root [testing conventions](../AGENTS.md#testing) apply. What's specific here:

- Test bundles run in `StuffTestHost` via the `unitTests` helper in
  `Project.swift` and link `TestHostSupport` (`show(_:perform:)`, `waitFor`).
- Use `ScriptedLocationSource` and `SwiftDataStore.inMemory()` — never
  `CoreLocationSource` or the user's on-disk/CloudKit store. The CloudKit
  remote-import path uses the `@_spi(Testing)`
  `inMemory(remoteChangeSource:)` + `ScriptedStoreRemoteChangeSource`.
- How screens render is pinned by the image snapshots in
  `WhereUI/SnapshotTests/` (the `WhereUISnapshotTests` bundle, run from the
  shared `StuffSnapshotTests` scheme + CI job, not `Stuff-iOS-Tests`) — see
  [`WhereUI/AGENTS.md`](WhereUI/AGENTS.md#testing). Don't add "hosts without
  crashing" smoke tests for surfaces those suites cover.
