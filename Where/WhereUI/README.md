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
  Settings "Data" group. `MainTabs` is built from the `WhereSession` the
  launch's `.ready` carries. The app injects the launch-built model + runner
  (`init(model:launcher:)`); a no-arg `init()` builds its own for previews and
  the hosted UI test.
- **`WhereModel`** — app-level state: the onboarding flag, the owned
  `WhereSession`, and the lifecycle intents (`attach(services:)`,
  `startSession(services:)` — which *returns* the session the launch's
  `start-session` step threads onward — `endSession()`, `resetPreferences()`).
- **`WhereSession`** — the always-on coordinator: tracking + location
  authorization state and the intents that drive them (`requestPermission()`,
  `startTracking()` / `stopTracking()`, `refreshWidgetSnapshot()`). It holds no
  presentation state of its own.
- **Scope-tiered models** — scene-scoped **`YearReportModel`** (the selected
  year's `YearReport`, its `LoadState`, and the manual-day edit intents), plus
  view-scoped **`ResolveModel`** (data-issue triage), **`BackupModel`**
  (export/import), and **`RemindersSettingsModel`** (notification prefs). Each
  orchestrates `WhereServices`; none reimplements Core rules.

### Reusable views & styling

- **`OnboardingView`** — the first-run flow, registered for the launch's
  `OnboardingGate` and handed its `LifecycleGateHandle` + the gate's
  `WhereSession`: a paged intro, then picking up to five primary US regions
  (map or searchable list) and giving each a look, then the
  location-permission ask. It commits the picks as the tracked-region set +
  appearances before resolving the gate. The intro also offers **Restore from
  a backup**, which imports a backup (`.replace`) and skips the manual
  pick/customize steps straight to the location ask.
- **`RegionPickerView` / `RegionCustomizeView`** — the shared primary-region
  picker (segmented map/list) and per-region color/emoji/icon customization,
  backed by `PrimaryRegionSelectionModel`. Reused by onboarding and the Settings
  `RegionsSettingsView` editor.
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

## Installation

`WhereUI` is a local SPM library in this repo (`Where/WhereUI`). Add it to a
target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourTarget", dependencies: [.target(name: "WhereUI")])
```

## Quick start

The app target is deliberately tiny — it builds the model + launch runner at
startup (so CoreLocation is wired for background relaunch) and hands them to
`RootView`:

```swift
import SwiftUI
import WhereUI

@main
struct WhereApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(model: appDelegate.model, launcher: appDelegate.launcher)
        }
    }
}
```

`RootView` applies `whereBroadwayRoot()` itself, so a host doesn't wrap it. For
a self-contained preview or UI test, the no-arg `RootView()` builds its own
model and a foreground launch runner.

## Design system

Appearance tokens — geometry, fonts, colors, motion — live in one place,
`WhereStylesheet`, a Broadway `BStylesheet` resolved from the environment. Views
read it with `@Environment(\.stylesheet)`; off the `View` tree (layout helpers,
tests) code uses `WhereStylesheet.default`. Tokens are grouped per component
(`CalendarStyle`, `AppIconStyle`, `CardStyle`, …) with shared scales for the
cross-cutting bits (`Spacing`, `Palette`, `Typography`, `Motion`). Most values
are fixed; a slice derives from accessibility traits (bigger tap targets at
large Dynamic Type, a flatter card under Reduce Transparency, a crossfaded
rather than rolling day count under Reduce Motion). See
[`AGENTS.md`](AGENTS.md#design-system--wherestylesheet) for how to consume and
extend it.

## Previews

Every previewable component ships a `#Preview` (wrapped in `#if DEBUG`) built
from **`PreviewSupport`** — synchronous, in-memory fixtures that never touch
disk, CloudKit, or CoreLocation. Pull services and models from there rather than
constructing them inline, and cover the empty / loaded / edge states, not just
the happy path. See the feature
[`Where/AGENTS.md`](../AGENTS.md#swiftui-views--previews).

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
directory. These files compile into the repo-wide `StuffSnapshotTests` bundle
alongside the other modules' image suites, which has its own scheme and CI job;
to re-record after an intentional UI change, forward the record mode into the
test process (see the
[SnapshotKitTesting README](../../Shared/SnapshotKitTesting/README.md#recording)
for the mode values):

```bash
TEST_RUNNER_SNAPSHOT_RECORD=failed mise exec -- tuist test StuffSnapshotTests \
  --no-selective-testing -- \
  -destination "platform=iOS Simulator,id=$(./simulator --os 27.0)"
```

then review and commit the images.
