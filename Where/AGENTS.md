# Where – Feature Shape

Where is an iOS/iPadOS app. It answers "what region was I in on which day?"
It ingests passive GPS (Visits + significant-change). It accepts user-asserted
history (manual coordinates, whole-day overlays, evidence like boarding passes).
It rolls everything up into per-day region presence and per-year reports. A day
counts for each region in its effective sample attribution plus additive manual
entries, unless an authoritative manual overlay replaces that presence.
Device removal and GPS corrections affect
effective attribution; raw observations remain available for review and backup.
A single day can belong to multiple regions.

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
- **All logging goes through [Periscope](../Shared/Periscope).** Define `@LogScope` namespaces and nested `@LogEvent` structs. Classify each payload property with `@LogField`. Emit it with a matching `.shared` or `.restricted` input. Use the `WhereLog` facade. Never write a direct `LogEvent` conformance or use a raw string. Each module
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
  [Spans](Guidance/logging.md#spans).
- **Location comes through the `LocationSource` protocol.**
  `CoreLocationSource` runs in production. `ScriptedLocationSource` runs in
  tests/previews. The bounded one-shot `requestCurrentLocation()` returns a
  typed, nonthrowing acquisition outcome. Live region decisions require a fix
  no more than 60 seconds old, with valid accuracy no worse than 1 km, whose
  uncertainty circle stays inside one tracked region. Passive valid samples
  remain historical evidence regardless of that live-decision cap.
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


## Required task guidance

Read the matching instructions before changing or reviewing that behavior, including its tests and callers outside this directory.
Read only the rows relevant to the task. These references preserve required contracts.

| Task | Required guidance |
| --- | --- |
| Logging, performance, or launch budgets | [Spans](Guidance/logging.md) |
| Scopes, startup, onboarding, reset, demo, or Flyover ownership | [Launch and demo](Guidance/launch.md) |
| UI, navigation, localization, or previews | [Presentation](Guidance/presentation.md) |
| Dates, calendars, ranges, or day persistence | [Dates](Guidance/dates.md) |
| Physical-device installation, archives, or signing | [Installation](Guidance/installation.md) |
| Any Where test or fixture change | [Testing](Guidance/testing.md) |

## Adding things

- **New library target:** add it in root [`Package.swift`](../Package.swift) under
  `Where/<Name>/Sources`. Add a hosted test bundle via `Project.swift`'s
  `unitTests` helper.
- **New region:** pure data. No `Region` case, no code. See
  [`RegionKit/README.md`](RegionKit/README.md#adding-a-region).
- **New evidence kind / sample source:** add the case. Follow the compile
  errors through the exhaustive switches.
- **New app icon:** run `./icons --add` (root
  [`AGENTS.md`](../.agents/references/build-system.md#managing-app-icons)). Never hand-edit the
  catalogs or manifest.
