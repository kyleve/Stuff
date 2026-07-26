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

- **`RootView`** — the app root: the launch sequence (via
  [`LifecycleKit`](../../Shared/LifecycleKit)) gated in front of `MainTabs`, the
  Liquid Glass tab bar over three tabs — Locations, Your Year, Settings.
  Elsewhere is an entry card on Locations, Resolve a Locations toolbar button,
  the data screens (attachments, logged days, regions) sit in the Settings
  "Data" group, and `AboutSettingsView` is the last Settings block (build
  identity, open-source notices, and bundled-data provenance, each vended by the
  module that owns it). The app injects the launch-built model + runner
  (`init(model:launcher:)`); a no-arg `init()` builds its own for previews and
  the hosted UI test.
- **`WhereModel`** — app-level state: the onboarding flag, the owned
  `WhereSession`, and the lifecycle intents (`attach(services:)`,
  `startSession()` / `endSession()`, `eraseAllData()`, `resetPreferences()`).
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

- **`OnboardingView`** — the first-run flow, driven by a `LifecycleStepUIBridge`:
  a paged intro, then picking up to five primary US regions (map or searchable
  list) and giving each a look, then the location-permission ask. It commits the
  picks as the tracked-region set + appearances before finishing. The intro also
  offers **Restore from a backup**, which imports a backup (`.replace`) and skips
  the manual pick/customize steps straight to the location ask.
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
the on-disk/CloudKit store); hosting tests mount views for their key states.
Internal types are reached via `@testable import WhereUI`.
