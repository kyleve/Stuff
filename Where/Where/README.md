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
| `Sources/WhereApp.swift` | `@main` `App`. One `WindowGroup` showing `RootView(model:launcher:)`, both taken from the delegate. |
| `Sources/AppDelegate.swift` | The composition root. Owns the app's single `WhereModel`, `IntentServices`, and `LifecycleRunner`; bootstraps Periscope's log store; installs the App Intents stack when the launch opens the store; indexes regions into Spotlight. |
| `Sources/WhereShortcuts.swift` | The `AppShortcutsProvider` — the spoken phrases Siri, Spotlight, and the Shortcuts app offer for the `WhereIntents` intents. |
| `Resources/AppIcon.xcassets` | The primary and alternate app icons. Generated and kept in sync by `./icons`; not hand-edited. |
| `Tests/WhereTests.swift` | Smoke tests over the shell wiring, hosted by the app itself. |

## Launch, briefly

`didFinishLaunching` does the wiring — not a SwiftUI `.task` — because
CoreLocation can relaunch the app with no UI at all, and only the delegate
callback is guaranteed to run. It registers the App Intents dependency, starts
logging, and builds a [`LifecycleKit`](../../Shared/LifecycleKit) runner with
the reason `.undetermined`, since the UIScene lifecycle can't yet distinguish a
user tap from a headless wake. The runner drives the background-safe launch
steps immediately and builds no view tree; when a scene actually activates,
`RootView` promotes the launch to `.userForeground` and the remaining steps run.

## Build & run

The target is declared in [`Project.swift`](../../Project.swift). Generate and
open the workspace with `./ide`, or install to a connected iPhone from the
command line with [`./Where/install`](../install) (macOS only, needs a signing
team — see [`Where/AGENTS.md`](../AGENTS.md#installing-to-a-device)).
