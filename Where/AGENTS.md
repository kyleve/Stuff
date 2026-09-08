# Where – Feature Shape

Where is an iOS/iPadOS app. It answers "what region was I in on which day?"
It ingests passive GPS (Visits + significant-change). It accepts user-asserted
history (manual coordinates, whole-day overlays, evidence like boarding passes).
It rolls everything up into per-day region presence and per-year reports. A day
"counts" for a region if **any** sample in that calendar day fell inside the
region's polygon. A single day can belong to multiple regions.

This file complements the root [`AGENTS.md`](../AGENTS.md). That file owns the
build system, formatting, and global conventions. Read that first.

## Modules

The layering stack runs bottom-up: **RegionKit** (geometry + region lookup) →
**WhereCore** (domain. It never imports SwiftUI/UIKit) → **WhereUI** (SwiftUI
views + view models) → the thin hosts (**Where** app, **WhereIntents**,
**WhereWidgets**, **WhereShareExtension**, **RegionViewer**). Each layer
reaches only *down*. Each module's own `AGENTS.md` / `README.md` is the
authority on what it is. Add domain behavior to WhereCore. Add presentation to
WhereUI. The app target stays tiny.

The DEBUG app has a second boot runtime from
[`Shared/Inspector`](../Shared/Inspector). `AppDelegate` selects either the
regular composition root or the standalone Inspector before launch. Inspector
is not a `WhereScope`. It must never construct regular app services.

## Layering

| Layer | Where | Owns |
|-------|-------|------|
| **Domain / services** | `WhereCore` (`WhereServices` collaborators) | Rules, detection, aggregation, persistence, side effects. Unit-test here. |
| **View model** | `WhereUI` (`WhereModel`, the `WhereSession` coordinator, the scoped `YearReportModel` / `ResolveModel` / `BackupModel` / `RemindersSettingsModel` / `DevicesSettingsModel`) | Lifecycle wiring, observable mirrors of service output, UI intent methods. |
| **Views** | `WhereUI` (`*View`) | Layout, navigation, localized copy, bindings. Never store I/O, detection, or cache/throttle policy. |

When in doubt, ask this: if the behavior would still be correct without
SwiftUI, it belongs in `WhereCore` (or on the coordinator / a scoped model —
still not a `View`).

Rules the code enforces and agents must preserve:

- **`WhereServices` is the domain entry point.** UI must never talk to the store
  or location source directly.
- **All store mutations run inside `WhereStore.perform { … }`.** The
  production store traps otherwise. Values cross the boundary. Never pass
  SwiftData records.
- **One read path.** Every committed write pings `WhereStore.changes()`.
  Readers refresh purely off that signal. Write intents commit. They do not
  refresh inline. Launch is a typed [`LifecycleKit`](../Shared/LifecycleKit)
  `LaunchPlan` (`WhereLaunch` in WhereUI). It renders in
  [`LifecycleKitUI`](../Shared/LifecycleKitUI)'s container in `RootView`.
- **All logging goes through [Periscope](../Shared/Periscope).** Use typed
  `LogEvent`s off the `WhereLog` facade. Never use a raw string. Each module
  keeps its `*Log.swift` event types in its `Sources/Logging/` folder. Not
  re-derivable from source: events log `.public`, so **keep PII out**. `info`
  = important success. `warning` = degraded-but-handled. `error`/`fault` =
  outright failure. Hot paths stay quiet by design. RegionKit emits a separate
  `"RegionKit"` root into the *same* `Periscope.shared`. Only the app process
  attaches a store. Widgets and the share extension are OSLog-only. App
  Intents run in the app process. An event about a store object stamps its
  `externalID` with the object's `store://` identity. RegionKit's parallel
  scheme is `region://` (see [`RegionKit/AGENTS.md`](RegionKit/AGENTS.md)).
- **Spans measure work and declare what "too slow" means.** See
  [Spans](#spans).
- **Location comes through the `LocationSource` protocol.**
  `CoreLocationSource` runs in production. `ScriptedLocationSource` runs in
  tests/previews. The one-shot `requestCurrentLocation()` returns `nil` rather
  than throwing when no fix is available.
- **Automatic recording consent is installation-local.** Stamp automatic GPS
  samples with their `RecordingDeviceID`. Route user-facing reads through
  `LocationHistoryReader`. Sync profiles, nickname events, advisory check-ins,
  and global removal tombstones. Never sync another device's recording toggle.
  Keep consent beside the backup-excluded installation identity. Phone
  onboarding recommends On only when no other active device recently reported
  recording. Tablet/other and explicit rejoins recommend Off.
- **Manual entries carry a `ManualEntryAudit`.** `DayJournal`'s write methods
  take an explicit `audit:` (no default). An additive backfill must not downgrade
  an authoritative row's regions. The newer audit always wins.

## Spans

Anything plausibly expensive is measured. Use `logger.measure(.name, budget:)`
on the owning type's `*Log`. Then the [Periscope](../Shared/Periscope) span
history can say which work is slow on a real device. It does not only say that
a screen felt slow.

- **Names are a typed `enum SpanName`** nested on the `*Log`. Never use a raw
  string. When a name carries a value, give it `CustomStringConvertible`. Then
  the history buckets by something readable — `step(resolve-scope)`,
  `loadRegion(us-CA)`, `detect(border-drift)` — not the Swift case's shape.
- **The budget is the promise, and it lives next to the work.** Overrunning it
  emits a `SpanOverdue` warning while the span keeps running. A budget is a
  claim about this specific call ("a widget publish must not take 2s"). It is
  not a timeout. Omit it only where no ceiling is meaningful — user-driven
  backup export/import, which scales with the archive.
- **Launch and reset steps declare a budget, not a `measure` call.** Every step
  in `WhereLaunch`'s plans conforms to `BudgetedLaunchStep`. It joins the plan
  through `.measured()`, which wraps it in `MeasuredStep`. A new step is
  spanned by declaring `budget`. `MeasuredStep` pointedly is not itself
  budgeted. Nothing can be measured twice into nested duplicate spans. Gates
  are exempt. The onboarding gate parks on the user. It has nothing to promise.
- **Span the work, not the property.** Composite orchestration that reflects
  user-perceived latency is worth a span even when its callees have their own
  (`WhereSession.appBecameActive`, `YearReportModel.refreshAll`, an intent's
  `perform`). A SwiftUI computed property re-evaluated per `body` pass is not.
  It would emit continuously and bury the real signal.
- **If a type needs spans but has no events,** give it a span-only facade. Use
  a `struct` conforming to `LogEvent` with a `private init` and an empty
  `message` (`ReportReaderLog`, `DataIssueScannerLog`, `PresenceCalendarLog`).
  It names spans without inventing an event nobody emits.
- **Spans emitted before a scope's durable store attaches are
  half-persisted.** A `SpanBegan` from the pre-sink window is only in OSLog.
  The `SpanEnded` lands in the store. Durations survive but the pair does not.
  That gap is Periscope's to close (P0 in its
  [`TODOs.md`](../Shared/Periscope/TODOs.md)). Do not work around it here.

## Scopes and the launch

- **A `WhereScope` is what the app is logged in *to*.** It is one open store's
  `WhereServices`, the `WherePreferences` driving it, and the durable log store
  they record into. It is created whole. `WhereSession` is built from one. A
  surface must not read one world's store against another's preferences.
- **Onboarding may prepare the real store only for recording-authority
  discovery.** Retain that exact store for scope resolution. Do not construct
  services, expose App Intents, start GPS, or open the log store until the
  user finishes choosing a world.
- **At most one scope is active and log-routing at a time.** Logging out — a
  reset, or leaving a demo — releases and tears down the scope. Logging back in
  builds a fresh one. Flyover is the narrow exception to "one open world". It
  may retain one separately built, in-memory demo scope beside the active app
  scope. It never activates or log-routes it. It never opens a second copy of
  the real store. Guards:
  `WhereResetTests.loggingOutReleasesTheScopeBeforeTheNextLoginOpensOne`.
  `WhereFlyoverWorldTests.buildsASeededSiblingWithoutActivatingIt`.
- **The onboarding gate declares `modes: .all`,** not the `.foreground`
  default. Parking a headless launch is the point. Keep recording confirmation
  in the backup-excluded installation sidecar. Then restoring backed-up
  `hasOnboarded` onto another device parks at the final choice page.
- **A gate carries no value.** A choice made *at* it reaches `resolve-scope`
  through `WhereModel`. That is the one step that reads model state rather than
  the trunk.
- **Ambient log sources start at process launch. The durable sink is a
  scope's.** Records emitted before a scope exists reach OSLog only.
- **Publish durable-log bring-up through `WhereModel.logStoreState`.** The
  active scope owns the store. The process model mirrors opening, ready,
  unavailable, and failed states for the DEBUG developer surface. Guards:
  `WhereModelTests`.

### Demo mode

- **Demo mode is a second scope, not a flag.** It uses an in-memory store
  seeded by `DemoDataBuilder`, in-memory preferences and log store, noop
  schedulers, outbox, and widget refresher. Enter from the onboarding intro.
  Leave from the first block of Settings (`WhereLaunch.exitDemoPlan`). Quitting
  mid-demo needs no teardown.
- **A demo leaves no mark on the device.** Anything that writes outside its own
  store is injected as a no-op or skipped at the call site (Spotlight indexing
  in `AppDelegate`). Settings hides the groups that would reach past it
  (`SettingsDestination.isAvailableInDemoMode`). A new persisting surface needs
  the same treatment.
- **`WhereModel` decides when a scope routes its logs.** A scope holds its log
  store from birth and routes only while active. One that opens while shadowed
  is remembered rather than attached. Guard:
  `DemoModeTests.aLogStoreOpeningLateNeverAttachesToAShadowedScope`.
- **Flyover builds but never activates its demo scope.** Its frames share that
  one in-memory world while the real app keeps its current scope. Dismissing
  Flyover releases the sibling. The process-global `WhereLog` facade remains a
  known exception tracked in [`TODOs.md`](TODOs.md).
- **The logging system is injected, not global.** `WhereModel.logSystem` has no
  default. A test must not silently attach sinks to `Periscope.shared`. (The
  `WhereLog` facade still emits into `.shared`. Pre-existing.)
- **Demo mode asks for no permission and presents a granted user.** The
  scripted location source reports `.always`. The noop schedulers are built
  `authorized: true`. No surface nags about a permission the demo cannot obtain.
  Guard: `DemoModeTests.demoPresentsAFullyGrantedUser`.
- **Views branch on `\.isInDemoMode`.** Seed once at `RootView` via
  `demoMode(of:)`. Guard: `DemoModeEnvironmentTests`.
- App Intents answer from the demo store while it is active. That is
  process-scoped and self-correcting on exit. It is accepted rather than
  special-cased (#150).

## Navigation

The logged-in shell is `MainTabs`. It has **three fixed tabs**: Locations, Your
Year, Settings. Everything else hangs off one of them. A new screen is a
pushed destination, a sheet, or a Settings row inside that shape. A fourth
tab is a product decision to raise before building. `MainTabs` passes the
scene-scoped `YearReportModel` by explicit init injection. The always-on
`WhereSession` coordinator travels in the environment. Settings is a
typed-route list (`SettingsSearch.swift`. Every switch is exhaustive). A
new drill-in is a set of compile errors to fill in. About stays the last
block. The demo-mode exit is the first.

Data, Privacy & Diagnostics, and About lead with the shared privacy passport.
Derive its detail from process-effective reporting channels, not saved pending
choices. Hide the persisted diagnostics destination in demo mode. About still
discloses the real process state.
The About screen renders three live sources. They are the generated attribution
report (`WhereCore.AppAttribution`), `RegionDataSource`, and `BuildInfo`.
Never hard-code a list in the view. A missing report or unstamped build
renders an honest empty state. Shipped libraries stay a separate section
from development tools. Keep its final passport sign-off linked to the public
project repository. Design and rationale: PR #140.

## Localization

All user-facing copy resolves through each module's `Localizable.xcstrings`
via Xcode's generated `LocalizedStringResource` symbols. A typo'd or removed
key is a compile error. Add a key as a **manual** entry first (so its symbol
generates). Then reference `.thatSymbol`. Never use a raw
`String(localized: "literal.key")`, a hand-maintained key facade, or an
English literal in `Text` / `errorDescription`.

- **WhereUI:** reference symbols directly. Composition, pluralization, and
  number/coordinate formatting go through
  [`WhereFormat`](WhereUI/Sources/Shared/WhereFormat.swift).
- **RegionKit:** region names resolve dynamically from `regions.json`
  (+ optional `localizationKey`). That is the one deliberate exception to static
  symbols (see [`RegionKit/AGENTS.md`](RegionKit/AGENTS.md)).
- **Extensions** use their own generated symbols for chrome and WhereUI's
  public helpers for shared copy. **DEBUG-only UI** is still localized.
- The catalogs carry a few value-less **auto-extracted** entries (`""`,
  `%lld`). They are Xcode's, not ours. An IDE build re-adds a deleted one. Remove
  the *source* literal instead. Catalogs stay byte-identical to Xcode's own
  serialization (root [Formatting](../AGENTS.md#formatting)).

## Dates

- **A logical day is a `CalendarDay` (Y-M-D), not a `Date`.** See
  [`WhereCore/AGENTS.md`](WhereCore/AGENTS.md). Never persist a day as an
  absolute instant.
- **Year bounds are half-open. Day ranges are inclusive**
  (`Date.calendarDays(through:in:)`, `CalendarDay.days(through:)`).
- **The app is Gregorian-only. Never use `Calendar.current`.** A non-Gregorian
  device calendar silently mismatches the stored reports. Use the calendar the
  owning type vends, or a fresh `Calendar(identifier: .gregorian)` with the
  current time zone (see `Calendar.whereIntents`).
- **Inject `Calendar`. Do not reach for globals.** Prefer calendar APIs over
  hardcoded day/weekday counts (`Calendar.dayCount(ofYear:)`).
- **Core layout APIs throw on failure.** Views surface
  `ContentUnavailableView` + log. Never use `!`.
- Shared date-range copy lives in `DateRangeFormatting`. WhereUI composition
  and value formatting go through `WhereFormat`.

## UI construction

Load the repo [`building-ui`](../.agents/skills/building-ui/SKILL.md) skill for
view/model placement, reuse, Broadway styling, layout, accessibility,
localization, previews, and image coverage. WhereUI previews use
[`PreviewSupport`](WhereUI/Sources/Preview/PreviewSupport.swift). Use
synchronous, in-memory fixtures. Never use disk, CloudKit, or CoreLocation.

## Adding things

- **New library target:** add it in root [`Package.swift`](../Package.swift) under
  `Where/<Name>/Sources`. Add a hosted test bundle via `Project.swift`'s
  `unitTests` helper.
- **New region:** pure data. No `Region` case, no code. See
  [`RegionKit/README.md`](RegionKit/README.md#adding-a-region).
- **New evidence kind / sample source:** add the case. Follow the compile
  errors through the exhaustive switches.
- **New app icon:** run `./icons --add` (root
  [`AGENTS.md`](../AGENTS.md#managing-app-icons)). Never hand-edit the
  catalogs or manifest.

## Installing to a device

`./Where/install` builds, signs, and installs the app onto a connected iPhone
from the CLI — macOS-only, one-time `./ide --team-id <id>` setup. It defaults
to the **Where Development** scheme with compiler optimizations forced on, so
DEBUG-only developer surfaces survive at near-Release speed. Pass
`--configuration Beta` for the TestFlight-style production identity or
`--configuration Release` for the App Store audience. Options:
`./Where/install --help`.

## Testing

Root [testing conventions](../AGENTS.md#testing) apply. What is specific here:

- **Formal protocol specs** live under [`Specifications/`](Specifications/README.md). Run them locally with [`./tla-check`](../tla-check) (opt-in, not CI). PlusCal is the editable model source. The checker translates an isolated copy under `.build/tla/runs/` before running TLC. Each concern also holds TLC configs, a `manifest.json`, and a README tying the model to production code and cited Swift tests.
- Test bundles run in `StuffTestHost` via the `unitTests` helper in
  `Project.swift`. They link `TestHostSupport` (`show(_:perform:)`, `waitFor`).
- Use `ScriptedLocationSource` and `SwiftDataStore.inMemory()`. Never use
  `CoreLocationSource` or the user's on-disk/CloudKit store. The CloudKit
  remote-import path uses the `@_spi(Testing)`
  `inMemory(remoteChangeSource:)` + `ScriptedStoreRemoteChangeSource`.
- How screens render is pinned by the image snapshots in
  `WhereUI/SnapshotTests/` (the `WhereUISnapshotTests` bundle, run from the
  shared `StuffSnapshotTests` scheme + CI job, not `Stuff-iOS-Tests`). See
  [`WhereUI/AGENTS.md`](WhereUI/AGENTS.md#testing). Do not add "hosts without
  crashing" smoke tests for surfaces those suites cover.
