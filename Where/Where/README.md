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

The target is declared in [`Project.swift`](../../Project.swift). Generate and
open the workspace with `./ide`, or install to a connected iPhone from the
command line with [`./Where/install`](../install) (macOS only, needs a signing
team — see [`Where/AGENTS.md`](../AGENTS.md#installing-to-a-device)).

## CloudKit rollout and device validation

The app target owns `iCloud.com.stuff.where`, the Push Notifications
entitlement, and the remote-notification background mode. Widgets and the share
extension intentionally have only the App Group entitlement: they write/read
local shared artifacts, while the app's single SwiftData container owns
CloudKit mirroring. Debug uses `.localOnly`; exercise sync with a Release-signed
build or use `./Where/install --cloudkit`. Release always selects `.cloudKit`.
The installer compiles the validation choice into that Debug app, so manual,
background, and CloudKit-push relaunches keep using CloudKit until another build
is installed without `--cloudkit`.

Before shipping a schema change:

1. Run `./Where/install --cloudkit` (or install a Release build) against the
   Development CloudKit environment and open the store so SwiftData initializes
   the additive schema.
2. Inspect the new fields/record types in CloudKit Console, then deploy that
   schema to Production before distributing the build.
3. On two devices signed into the same iCloud account, open Settings → Devices
   and verify both generic hardware profiles arrive; rename one and verify the
   nickname syncs.
4. From the carried device, turn automatic recording off for the left-behind
   device. Verify its row says it is waiting, and that locations at/after the
   cutoff disappear from reports as soon as the policy syncs.
5. Open the left-behind device. Verify it stops monitoring, acknowledges Off,
   and the waiting state clears on the carried device. Re-enable it and verify
   new locations appear again.
6. Archive the non-current device and verify it is hidden without losing older
   report history. Export and replace-import a backup; verify history and names
   round-trip, archived imported devices stay hidden, file-absent devices stay
   retired, and every visible device is Off until explicitly re-enabled.

On a fresh install, onboarding recommends automatic recording On for an iPhone
and Off for an iPad/other device, then requires the user to confirm. Existing
installations created before that choice was introduced revisit only the final
recording page once; enabling is the only path that asks for location access.
