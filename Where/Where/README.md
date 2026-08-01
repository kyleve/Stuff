# Where (app target)

The iOS/iPadOS and Mac Catalyst app bundle for **Where**. It is deliberately a
shell: it starts the process, builds the objects everything else shares, and
shows `WhereUI`'s `RootView`. All the behavior lives in the modules below it —
[`WhereCore`](../WhereCore) (domain, persistence, GPS),
[`WhereUI`](../WhereUI) (screens and view models),
[`WhereIntents`](../WhereIntents) (Siri/Shortcuts), and
[`RegionKit`](../RegionKit) (geometry) — plus the
[`WhereWidgets`](../WhereWidgets) and
[`WhereShareExtension`](../WhereShareExtension) extensions it embeds. The
Catalyst bundle also embeds the native
[`WhereMenuBar`](../WhereMenuBar) login item; the user enables it from
Settings → Devices.

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
CoreLocation can relaunch the iPhone/iPad app with no UI at all, and only the
delegate callback is guaranteed to run. It registers the App Intents
dependency, starts logging, and builds a
[`LifecycleKit`](../../Shared/LifecycleKit) runner with the reason
`.undetermined`, since the UIScene lifecycle can't yet distinguish a user tap
from a headless wake. The runner drives the background-safe launch steps
immediately and builds no view tree; when a scene actually activates,
`RootView` promotes the launch to `.userForeground` and the remaining steps
run. Mac Catalyst uses the same lifecycle without constructing CoreLocation
and manages the recording policies of synced iPhones and iPads.

## Build & run

The target is declared in [`Project.swift`](../../Project.swift). Generate the
workspace with `./ide --no-open`. Build Mac Catalyst with the shared
`Where-Catalyst` scheme; install to a connected iPhone from the command line
with [`./Where/install`](../install) (macOS only, needs a signing team — see
[`Where/AGENTS.md`](../AGENTS.md#installing-to-a-device)).

## CloudKit rollout and device validation

The app target owns `iCloud.com.stuff.where` plus the platform APNs entitlement
and remote-notification background mode. Widgets and the share extension
intentionally have only the App Group entitlement: they write/read local shared
artifacts, while the app's single SwiftData container owns CloudKit mirroring.
Debug uses `.localOnly`; exercise sync with a Release-signed build.

Before shipping a schema change:

1. Install a Release build against the Development CloudKit environment and
   open the store so SwiftData initializes the additive schema.
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
   report history. Export and replace-import a backup and verify device names,
   raw samples, policy history, and archived state round-trip.
