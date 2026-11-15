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

The dependency order is RegionKit → WhereCore → WhereUI → app/intent/widget/share-extension hosts. Reach only downward.
Module READMEs describe APIs; module instructions define local contracts.

## Layering

WhereCore owns domain rules, persistence, and side effects. WhereUI models own observable mirrors, lifecycle wiring, and UI intents.
Views own presentation; the app target stays a composition host. The [building-ui skill](../.agents/skills/building-ui/SKILL.md) defines the shared UI boundary.
The DEBUG Inspector runtime is selected before launch, is not a `WhereScope`, and must not construct regular app services.

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

| Task | Required guidance |
| --- | --- |
| Logging, performance, or launch budgets | [Spans](Guidance/logging.md) |
| Scopes, startup, onboarding, reset, demo, or Flyover ownership | [Launch and demo](Guidance/launch.md) |
| UI, navigation, localization, or previews | [Presentation](Guidance/presentation.md) |
| Dates, calendars, ranges, or day persistence | [Dates](Guidance/dates.md) |
| Physical-device installation, archives, or signing | [Installation](Guidance/installation.md) |
| Any Where test or fixture change | [Testing](Guidance/testing.md) |

## Adding things

New regions are data, not enum cases: see [RegionKit](RegionKit/README.md#adding-a-region).
For new evidence/sample-source cases, follow the exhaustive-switch compile errors.
