# Where (app target)

The iOS/iPadOS app bundle for **Where**. It is deliberately a shell: it starts
the process, builds the objects everything else shares, and shows `WhereUI`'s
`RootView`. All the behavior lives in the modules below it —
[`WhereCore`](../WhereCore) (domain, persistence, GPS),
[`WhereUI`](../WhereUI) (screens and view models),
[`WhereIntents`](../WhereIntents) (Siri/Shortcuts), and
[`RegionKit`](../RegionKit) (geometry) — plus the
[`WhereWidgets`](../WhereWidgets) and
[`WhereShareExtension`](../WhereShareExtension) extensions it embeds.

For what the app *does*, start at the feature overview in
[`Where/AGENTS.md`](../AGENTS.md). For the rules that apply when editing this
target, see [`AGENTS.md`](AGENTS.md).

## What's in here

| File | Role |
|------|------|
| `Sources/WhereApp.swift` | `@main` `App`. One `WindowGroup` rendering the selected runtime's type-erased root. |
| `Sources/AppDelegate.swift` | The boot router. Selects one `WhereApplicationRuntime` in its initializer and forwards lifecycle callbacks. |
| `Sources/WhereBuildEnvironment.swift` | Validates the host-only audience condition and maps the generated Info.plist values to storage, App Group, widget refresh, and primary-icon dependencies. |
| `Sources/RegularApplicationRuntime.swift` | Owns the app's single `WhereModel`, `IntentServices`, and `LifecycleRunner`; starts logging, installs the App Intents handoff, and indexes Spotlight. |
| `Sources/WhereInspectorApplicationRuntime.swift` | DEBUG-only alternate runtime. Configures the standalone Inspector without constructing regular app systems. |
| `Sources/WhereApplicationRuntime.swift` | The class-bound launch/root-view protocol shared by both runtimes. |
| `Sources/WhereShortcuts.swift` | The `AppShortcutsProvider` — the spoken phrases Siri, Spotlight, and the Shortcuts app offer for the `WhereIntents` intents. |
| `Resources/AppIcon.xcassets` | The primary and alternate app icons. Generated and kept in sync by `./icons`; not hand-edited. |
| `Tests/WhereTests.swift` | Smoke tests over the shell wiring, hosted by the app itself. |

## Launch, briefly

`AppDelegate.init` makes one boot-time selection. In release this is always
`RegularApplicationRuntime`; in DEBUG a dedicated UserDefaults suite can select
`WhereInspectorApplicationRuntime` for the next process. Every later callback
and root-view request uses protocol dispatch, so no feature or lifecycle code
switches on a mode. Before that selection, DEBUG boot completes any store-family
recovery Inspector scheduled in the prior process. A failed cleanup forces the
Inspector runtime and keeps the request visible instead of starting regular
systems against the store.

In the regular runtime, `didFinishLaunching` does the wiring — not a SwiftUI `.task` — because
CoreLocation can relaunch the app with no UI at all, and only the delegate
callback is guaranteed to run. It registers the App Intents dependency, starts
logging, and builds a [`LifecycleKit`](../../Shared/LifecycleKit) runner with
the reason `.undetermined`, since the UIScene lifecycle can't yet distinguish a
user tap from a headless wake. The runner drives the background-safe launch
steps immediately and builds no view tree; when a scene actually activates,
`RootView` promotes the launch to `.userForeground` and the remaining steps run.

The Inspector runtime returns its standalone `InspectorView` and starts none of
the model, launch, CoreLocation, notification, Periscope pipeline, App Intents,
or Spotlight systems. It opens Where and Periscope containers only through
their schema adapters for inspection. Each source's containment root is derived
from the adapter's exact store URL, since SwiftData may place the Periscope
database in the app-group container. A container that cannot open remains listed
with its error and a confirmed action that deletes only its configured store
family and Periscope crash-journal directory before removing the source from the
current Inspector session and scheduling one pre-runtime cleanup pass for the
next process. Its exit control selects the regular runtime for the next manual
relaunch; neither runtime swaps live.

## Build & run

The target is declared once in [`Project.swift`](../../Project.swift), with
three audience schemes: **Where Development** (`Debug`, isolated bundle/App
Group, local-only data), **Where Beta** (`Beta`, production identity and
CloudKit), and **Where App Store** (`Release`, production identity and
CloudKit). The manifest injects audience values into the app and extensions;
only those host targets receive the matching `WHERE_*` compiler condition.
Generate the workspace with `./ide --no-open`, or install to a connected iPhone
from the command line with [`./Where/install`](../install) (macOS only, needs a
signing team — see [`Where/AGENTS.md`](../AGENTS.md#installing-to-a-device)).
