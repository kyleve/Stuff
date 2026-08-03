# WhereUI

The SwiftUI layer of the **Where** app: every screen the user sees, the shared
components and widget views, and the `@Observable` view models that turn
`WhereCore`'s domain services into something SwiftUI can render. It sits on top
of `WhereCore` (domain, persistence, GPS) and `RegionKit` (geometry) — both of
which stay UI-free — and leans on the Broadway design system for its tokens. The
app target is a thin shell that builds a model at launch and shows WhereUI's
`RootView`; the **WhereWidgets** extension reuses WhereUI's views to render a
published snapshot.

For the module's *rules* — the domain/presentation layering, localization,
required previews, and how to extend the `WhereStylesheet` design system — see
the feature [`Where/AGENTS.md`](../AGENTS.md) and this module's
[`AGENTS.md`](AGENTS.md). This file is the human-facing tour.

## What you get

### App shell & view models

- **`RootView`** — the app root: the typed launch plan (via
  [`LifecycleKit`](../../Shared/LifecycleKit), rendered by
  [`LifecycleKitUI`](../../Shared/LifecycleKitUI)'s container) gated in front of
  `MainTabs`, the Liquid Glass tab bar over three tabs — Locations, Your Year,
  Settings. Elsewhere is an entry card on Locations, Resolve a Locations toolbar
  button, and the data screens (attachments, logged days, regions) sit in the
  Settings "Data" group. Backup and destructive data management share one Data
  drill-in. `AboutSettingsView` is the last Settings block — build
  identity, the app's generated attribution report (linked libraries and
  development tools as separate sections), and bundled-data provenance, each
  vended by whoever owns it rather than listed in the view; it renders an
  explicit "no report" state, since only the app bundle carries one. `MainTabs`
  is built from the `WhereSession` the launch's `.ready` carries. The app
  injects the launch-built model + runner
  (`init(model:launcher:)`); a no-arg `init()` builds its own for previews and
  the hosted UI test.
- **Developer tools** — DEBUG-only logging, span, region-map, Flyover, and
  next-launch Inspector controls. The global launcher's accordion only updates
  `InspectorModeController`; the current regular runtime continues until the
  developer relaunches. The Logs destination is always present: before its
  durable store is ready it reports whether the open is still running,
  unavailable, or failed with the actual error.
- **`WhereLaunch`** — the launch, reset, and exit-demo plans themselves. Every
  step declares how long it should take (`BudgetedLaunchStep`) and joins the
  plan through `.measured()`, so each run is one Periscope span named after
  the step (`step(resolve-scope)`) that warns while it overruns its budget —
  the launch's cost breaks down per step instead of arriving as one slow
  splash. (The onboarding gate is the one unmeasured node: it parks on the
  user.)
- **`WhereScope`** — what the app is logged in *to*: one open store's
  `WhereServices`, the `WherePreferences` driving it, and the durable log store
  they record into, created whole and never reconfigured. `WhereModel` owns
  which scope is active; `WhereSession` is built from one, so a logged-in
  surface can't read one world's store against another's preferences. Two
  kinds, both reached through `WhereModel`: the real one opens the app's single
  on-disk store, and `makeDemoScope()` builds a seeded in-memory world that
  leaves nothing behind. Its log sink is registered on an **injected**
  `Periscope` — and only while `WhereModel` says the scope is active — with
  routing modelled as one state (`pending` / `routing` / `idle` / `failed`), so
  a store that finishes opening while the scope is shadowed is remembered rather
  than routed into. `WhereModel.logStoreState` mirrors the active scope's
  asynchronous bring-up for direct SwiftUI observation. When the durable store
  opens, its bring-up is spanned (`openLogStore`) and history is trimmed with
  `LogHistoryPruner` (a 100-day window *and* a 50k-event ceiling, so the store is
  bounded however heavily the device logs).
- **`WhereModel`** — app-level state that outlives any one scope: the backed-up
  onboarding flag, the separately injected non-backed-up installation
  recording context (including stable first-profile/policy timestamps), the
  active `WhereScope`, the owned `WhereSession`, and the lifecycle intents
  (`activate(scope:)`, `startSession(scope:)` — which
  *returns* the session the launch's `start-session` step threads onward —
  `endSession()`, `resetPreferences()`).
- **`WhereSession`** — the always-on coordinator: tracking + location
  authorization state and the intents that drive them (`requestPermission()`,
  per-device recording changes, `startTracking()` / `stopTracking()`,
  `refreshWidgetSnapshot()`). It holds no presentation state of its own.
- **Scope-tiered models** — scene-scoped **`YearReportModel`** (the selected
  year's `YearReport`, its `LoadState`, and the manual-day edit intents), plus
  view-scoped **`ResolveModel`** (data-issue triage), **`BackupModel`**
  (export/import plus a mirror of the scope-owned committed-cleanup gate),
  **`RemindersSettingsModel`** (notification prefs), and
  **`DevicesSettingsModel`** (synced installation names, policy, status, and
  archival). Each orchestrates `WhereServices`; none reimplements Core rules.

### Reusable views & styling

- **`OnboardingView`** — the first-run flow, registered for the launch's
  `OnboardingGate` and handed its `LifecycleGateHandle`. The gate roots the
  trunk, so there is no session (and no open store) behind it: a paged intro,
  then picking up to five primary US regions (map or searchable list) and
  giving each a look, then verifying this installation's automatic-recording
  choice. Phones recommend On; tablets/other devices recommend Off, and only
  an enabled confirmation requests location permission. A restored device can
  inherit the backed-up onboarding flag but not the installation sidecar, so it
  skips straight to that final page. Finishing logs in to the real scope — the
  app's one store open — and commits the picks as the tracked-region set +
  appearances before resolving the gate. The intro also offers **Restore from
  a backup**, which skips the manual pick/customize steps, verifies this
  installation's recording choice, then opens the store and imports the backup
  after asking whether to **Merge** (recommended, preserving existing data) or
  **Replace** (destructive, starting from the backup); and **Explore a demo**,
  which builds a throwaway in-memory world behind a captioned launch splash and
  enters it. Once an onboarding import commits, its summary is retained and
  a two-phase marker remains in the backup-excluded sidecar until onboarding is
  acknowledged. A terminal tombstone remains after recovery is cleared so a
  cold launch can repair an onboarding preference that had not reached disk,
  but never offer the same archive for import again. Every cold launch also
  resolves a Settings import marker before handing services to App Intents or
  registering the recording device, so Replace cleanup finishes before GPS can
  reopen or drain an obsolete outbox.
- **`RegionPickerView` / `RegionCustomizeView`** — the shared primary-region
  picker (segmented map/list) and per-region color/emoji/icon customization,
  backed by `PrimaryRegionSelectionModel`. Reused by onboarding and the Settings
  `RegionsSettingsView` editor.
- **`DevicesSettingsView`** — Settings’ per-installation automatic-recording
  controls. It distinguishes desired policy from acknowledged physical state,
  labels the current installation, permits synced nicknames, and archives only
  remote devices while preserving their history.
- **Widget views** — the shared renderers the **WhereWidgets** extension draws
  with: `TodayWidgetView`, `YearTotalsWidgetView`, and the accessory family
  (`TodayInlineAccessoryView`, `TodayCircularAccessoryView`,
  `YearTotalsRectangularAccessoryView`). Each takes a `WidgetSnapshot`.
- **`RegionStyle` / `RegionStyleResolver`** — a region's symbol, emoji, and
  tint, shared across cards, calendar dots, and timelines. Views resolve it from
  `@Environment(\.regionStyles)` (`regionStyles.style(for: region)`), seeded by
  `whereBroadwayRoot(regionStyles:)` — from `WhereSession`'s live resolver in the
  app, the `WidgetSnapshot` in the widget process, and services in App Intents —
  falling back to a deterministic default from `RegionAppearanceCatalog`.
- **`whereBroadwayRoot()`** — seeds the Broadway design-system context so
  descendants resolve the `WhereStylesheet` tokens (see [Design
  system](#design-system)). Applied by `RootView` and by each widget.
- **`RegionMapView`** — the developer region-map tool (also hosted standalone by
  the RegionViewer Mac Catalyst app).
- **Flyover** — a DEBUG-only all-screens browser reached from the developer
  launcher's accordion. It renders the app's screens on a zoomable navigation
  canvas or linear list, shows push/modal routes, switches global device and
  accessibility traits, and opens any frame in a live focused inspector.

## Installation

`WhereUI` is a local SPM library in this repo (`Where/WhereUI`). Add it to a
target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourTarget", dependencies: [.target(name: "WhereUI")])
```

## Quick start

The app target is deliberately tiny. It selects one application runtime, then
forwards the process launch and root view:

```swift
import SwiftUI
import WhereUI

@main
struct WhereApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            appDelegate.runtime.makeRootView()
        }
    }
}
```

The regular runtime owns the model and launch runner; the DEBUG Inspector
runtime supplies an entirely separate root. `RootView` applies
`whereBroadwayRoot()` itself, so a host doesn't wrap it. For
a self-contained preview or UI test, the no-arg `RootView()` builds its own
model and a foreground launch runner.

## Design system

Appearance tokens — geometry, fonts, colors, motion — live in one place,
`WhereStylesheet`, a Broadway `BStylesheet` resolved from the environment. Views
read it with `@Environment(\.stylesheet)`; off the `View` tree (layout helpers,
tests) code uses `WhereStylesheet.default`. The active sheet is seeded by
`whereBroadwayRoot()` at the app root and in each Broadway-root-less consumer
(WhereWidgets); with no root present, resolution falls back to `.default`.
The rules for what may and may not live in the sheet are in
[`AGENTS.md`](AGENTS.md#design-system--wherestylesheet).

### Using tokens

For a component with more than one look, resolve the variant once: vend a
resolved sub-spec and read it into a single property rather than branching
through the body. `RegionSummaryCard` reads `stylesheet.card[variant]` into a
`card` so its render is straight-line, with no `compact ? … : …` scattered
across ~30 values.

### Adding tokens — per-component style groups

Group a component's whole appearance into one nested `Equatable` struct
instead of adding loose properties to the top level. The stored properties
declared at the top of `WhereStylesheet` are the live list of groups; two are
worth copying as templates: `CardStyles` (a variant axis behind a `subscript`)
and `CalendarStyle` (nested sub-parts). To add one:

1. Define the struct in a `WhereStylesheet` extension with a doc comment
   saying which component it styles and any invariants; nest further structs
   for sub-parts (e.g. `CalendarStyle.MonthStyle`, `AppIconStyle.PanelStyle`).
2. Give it a `static let standard` holding the fixed geometry, and add a
   stored property on `WhereStylesheet` defaulted to it.
3. If a look varies (the `compact` card), model the axis as a `Variant` enum
   and expose a `subscript` on the styles struct so callers read one resolved
   spec.

Reach for a shared group only for genuinely cross-component values: the
generic point scale on `Spacing`, one-off element sizes on `Size`, app-wide
colors not owned by a single component on `Palette`, the few bespoke display
faces on `Typography`, and animation tokens on `Motion`.

### Trait-aware tokens

Most tokens are fixed; a slice derives from the `BContext` traits in
`init(context:)` — read the live set off that initializer. Today it grows
day-grid tap targets at accessibility Dynamic Type sizes, flattens the card
glow under Reduce Transparency, and crossfades the cards' day count under
Reduce Motion.

### Per-region styling

`RegionStyle` is data-driven and resolved through the environment: views read
`@Environment(\.regionStyles)` (a `RegionStyleResolver`) and call
`regionStyles.style(for: region)`. The resolver is seeded by
`whereBroadwayRoot(regionStyles:)`: the app passes `WhereSession`'s live
resolver (updated on launch + `changes()`), the widget process one built from
its `WidgetSnapshot`, and App Intents snippets one from their services; the
default empty resolver yields the fallback looks
(`RegionAppearanceCatalog.defaultAppearance(for:)`) for previews and the
region-map viewer. The catalog also owns the selectable color/emoji/symbol
option lists the picker shows.

Regular `RegionSummaryCard`s ask the root-owned `RegionOutlinePathCache` for a
medium SwiftUI path for the large security-print watermark and a small path for
the seal inside the circular entry stamp. A separate micro path is repeated as
a tangent-aligned microprint border around the card's inner perimeter. The UI
cache derives all four resolutions from RegionKit's one cached source outline
using its stateless simplifier; compact cards retain the simpler symbol
treatment. Security-print layers use normal compositing in light mode and
Screen in dark mode, so the same tinted details darken pale glass but lighten
dark glass.
Live tilt is observed only by the sheen overlay, so its 60 Hz updates do not
invalidate the card's text or Canvas artwork. The card adds no standalone edge
stroke; its containing Liquid Glass surface owns the subtle outer border so
direct and production rendering do not diverge.

DEBUG builds include Card Designer Studio under Settings → Appearance. It
edits a versioned, persisted draft of the regular, compact, and shared card
presentation, previews both appearances with live tilt, and exports the full
result—or only its changes from the app defaults—as shareable or clipboard JSON
and Swift. The draft affects the rest of the app only while “Apply to App” is
enabled; that switch intentionally resets on every launch.

## Previews

Every previewable component ships a `#Preview` (wrapped in `#if DEBUG`) built
from **`PreviewSupport`** — synchronous, in-memory fixtures that never touch
disk, CloudKit, or CoreLocation. Pull services and models from there rather than
constructing them inline, and cover the empty / loaded / edge states, not just
the happy path. See the feature
[`Where/AGENTS.md`](../AGENTS.md#swiftui-views--previews).

## Flyover

`Sources/Developer/Flyover` owns an explicit `WhereFlyoverScreenID` catalog.
The enum is exhaustive and completeness-tested, so adding a top-level screen
produces one obvious registration update rather than depending on source
scanning or a macro that cannot discover navigation across the module.

Opening Flyover asynchronously builds one `WhereScope.demo` and shares its
seeded in-memory services, preferences, and session across live frames. That
scope is never activated and never log-routed; the app's current scope remains
untouched. The loader constructs and retains the completed catalog once, so
host-view updates preserve those frame fixtures and their controls. Synthetic
`PreviewSupport` states fill the gaps the demo data cannot express cleanly
(empty, failed, unavailable, widget, and intent-snippet states). Frame-local
controls can mutate only their own observable fixture—for example, Locations
can show or hide its Resolve toolbar item—and Reset restores that fixture.

Overview frames ignore hit testing so embedded navigation containers cannot
fight the canvas. Leaf screens receive an isolated navigation stack so their
titles, toolbar items, and destinations render inside the frame rather than
escaping into the Developer Tools stack; app roots, widgets, and snippets opt
out. Selecting the inspect button opens the same screen in a full-screen
interactive viewport. Flyover's appearance, device, Dynamic Type, contrast,
layout-direction, and bold-text choices are session-only and apply only to
registered content.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereUITests`), hosted in `StuffTestHost`
and linking `TestHostSupport` (`show(_:perform:)`, `waitFor`). View models are
driven against a `ScriptedLocationSource` + in-memory `SwiftDataStore` (never
the on-disk/CloudKit store). Internal types are reached via
`@testable import WhereUI`.

How screens *look* is pinned separately: every top-level screen, widget, and
app-flow surface has matrixed image snapshots (light/dark, Dynamic Type,
iPhone/iPad, contrast, right-to-left, VoiceOver annotations) in
[`SnapshotTests/`](SnapshotTests), with reference images under
`SnapshotTests/__Snapshots__/` in Git LFS. Each view declares its matrix via a
`SnapshotProviding` conformance **in its own source file**, shared with its
`#Preview` cutsheet (`Self.snapshotPreviews`); there is one `FooSnapshotTests`
suite per view, so each view's references live in their own `__Snapshots__/`
directory. They build as this module's own `WhereUISnapshotTests` bundle, which
runs alongside the other modules' image suites in the shared
`StuffSnapshotTests` scheme and its CI job;
to re-record after an intentional UI change (see the
[SnapshotKitTesting README](../../Shared/SnapshotKitTesting/README.md#recording)
for the mode values):

```bash
./test --snapshots --record failed
```

then review and commit the images.
