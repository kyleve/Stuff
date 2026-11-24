# Where (app target)

The iOS/iPadOS app bundle for **Where**.
It is deliberately a shell.
It starts the process, builds the objects everything else shares, and shows `WhereUI`'s `RootView`.
All the behavior lives in the modules below it — [`WhereCore`](../WhereCore) (domain, persistence, GPS), [`WhereUI`](../WhereUI) (screens and view models), [`WhereIntents`](../WhereIntents) (Siri/Shortcuts), and [`RegionKit`](../RegionKit) (geometry) — plus the [`WhereWidgets`](../WhereWidgets) and [`WhereShareExtension`](../WhereShareExtension) extensions it embeds.

For what the app *does*, start at the feature overview in [`Where/AGENTS.md`](../AGENTS.md).
For the rules that apply when editing this target, see [`AGENTS.md`](AGENTS.md).

## What's in here

| File | Role |
|------|------|
| `Sources/WhereApp.swift` | `@main` `App`. One `WindowGroup` rendering the selected runtime's type-erased root. |
| `Sources/AppDelegate.swift` | The boot router. Resolves the audience and process reporting preferences, starts the reporting controller, selects one `WhereApplicationRuntime`, and forwards lifecycle callbacks. |
| `Sources/WhereBuildEnvironment.swift` | Validates the host-only audience condition and maps the generated Info.plist values to storage, App Group, widget refresh, and primary-icon dependencies. |
| `Sources/DiagnosticReportingController.swift` | Owns the launch-only Bitdrift channels and revisioned Periscope remote sink for the process. |
| `Sources/RegularApplicationRuntime.swift` | Owns the app's single `WhereModel`, `IntentServices`, and `LifecycleRunner`. Starts logging, installs the App Intents handoff, and indexes Spotlight. |
| `Sources/WhereInspectorApplicationRuntime.swift` | DEBUG-only alternate runtime. Configures the standalone Inspector without constructing regular app systems. |
| `Sources/WhereApplicationRuntime.swift` | The class-bound launch/root-view protocol shared by both runtimes. |
| `Sources/WhereShortcuts.swift` | The `AppShortcutsProvider` — the spoken phrases Siri, Spotlight, and the Shortcuts app offer for the `WhereIntents` intents. |
| `Resources/AppIcon.xcassets` | The primary and alternate app icons. Generated and kept in sync by `./icons`. Not hand-edited. |
| `Tests/WhereTests.swift` | Smoke tests over the shell wiring, hosted by the app itself. |

## Launch, briefly

`AppDelegate.init` makes one boot-time selection.
In release this is always `RegularApplicationRuntime`.
In DEBUG, `WhereDeveloperLaunchController` persists one mutually exclusive
next-process choice: the standalone Inspector runtime or a configured,
one-shot demo inside the regular runtime. The demo request is consumed as the
regular runtime is built. Its first launch step activates an in-memory scope
before onboarding can open the real store. A later process therefore returns
to the user's untouched data unless another demo is scheduled.
Every later callback and root-view request uses protocol dispatch, so no feature or lifecycle code switches on a mode.
Before that selection, DEBUG boot completes any store-family recovery Inspector scheduled in the prior process.
A failed cleanup forces the Inspector runtime and keeps the request visible instead of starting regular systems against the store.

In the regular runtime, `didFinishLaunching` does the wiring — not a SwiftUI `.task` — because CoreLocation can relaunch the app with no UI at all, and only the delegate callback is guaranteed to run.
It registers the App Intents dependency, starts logging, and builds a [`LifecycleKit`](../../Shared/LifecycleKit) runner with the reason `.undetermined`, since the UIScene lifecycle cannot yet distinguish a user tap from a headless wake.
The runner drives the background-safe launch steps immediately and builds no view tree.
When any scene activates, `WhereApp` forwards its aggregate scene phase to the runtime. The runtime promotes the launch to `.userForeground`, starts compatibility polling, verifies access, and activates the admitted session. Duplicate activity values coalesce; inactive/background transitions stop polling and cancel the remaining activation work. The launcher keeps owning its background-safe drive. `RootView` only supplies its scene-specific visibility to the first-reveal presentation.

Before either the regular or Inspector runtime receives that callback, the app
captures diagnostic preferences. It starts Bitdrift only if crash reports,
session replay, or remote logs require it. Fatal reporting and replay stay at
that launch snapshot. Remote Periscope forwarding attaches, updates, drains,
and detaches live. The same `WherePreferences` instance feeds `WhereModel`.
An all-Off launch never starts the SDK. Performance tracing is not enabled by
this setup. If the provider does not start, the app records a typed local error
event. The regular runtime also shows the error in Privacy & Diagnostics.

Baseline forwarding sends stable event metadata and shareable classified fields only.
Diagnostic forwarding uses the event's filtered projection, never its raw Codable payload.
Independent controls govern identifiers, locations, user content, and other personal data.
The adapter uses PeriscopeCore's `LogContextExportRequirements` for context permissions. The UI control group does not define these requirements.
Local-only fields remain excluded with every control enabled.
Unclassified tags, scope paths, and attachment metadata require all four built-in grants.
Folded ambient snapshots remain local because they do not retain field policies. Classified ambient events retain their own export rules.
Neither mode sends attachment bytes. If payload or JSON encoding fails, the sink skips that record.
It counts the failure and reports it through OSLog to prevent Periscope recursion.

The Inspector runtime returns its standalone `InspectorView` and starts none of the model, launch, CoreLocation, notification, Periscope pipeline, App Intents, or Spotlight systems.
It opens Where and Periscope containers only through their schema adapters for inspection.
Each source's containment root is derived from the adapter's exact store URL, since SwiftData may place the Periscope database in the app-group container.
A container that cannot open remains listed with its error and a confirmed action that deletes only its configured store family and Periscope crash-journal directory before removing the source from the current Inspector session and scheduling one pre-runtime cleanup pass for the next process.
Its exit control selects the regular runtime for the next manual relaunch.
Neither runtime swaps live.

The regular runtime creates one InstallerKit `UpdateService` and `UpdateModel` for configured Development builds, including local Xcode and `Where/install` builds.
It injects the presentation model through `RootView`.
`MainTabs` starts checks only in the foreground, outside demo mode.
Local builds can install published builds through Other Builds. Reinstall from Xcode or `Where/install` to return to Local.
Test processes, Beta, and App Store builds have no update model.

## Build & run

The target is declared once in [`Project.swift`](../../Project.swift), with
three audience schemes: **Where Development** (`Debug`, isolated bundle/App
Group, local-only data), **Where Beta** (`Beta`, production identity and
CloudKit), and **Where App Store** (`Release`, production identity and
CloudKit). The manifest injects audience values into the app and extensions;
only those host targets receive the matching `WHERE_*` compiler condition.
Generate the workspace with `./ide --no-open`, or install to a connected iPhone
from the command line with [`./Where/install`](../install) (macOS only, needs a
signing team — see [`Where/AGENTS.md`](../Guidance/installation.md#installing-to-a-device)).
Use `./Where/install --dry-run` to resolve the exact paired physical device and
report the build/install/launch plan without performing it.

## CloudKit rollout and device validation

The regular runtime verifies a separate compatibility record before opening SwiftData.
Every build injects a transport and receipt store into the same coordinator. Development uses a local transport; the cloud-capable transport also uses local mode when CloudKit confirms no account. Restricted or unavailable account states do not grant local access. The host build environment resolves compiler flags once, and the runtime retains its configured storage policy. Bootstrap applies the verified domain before opening the container. Demo is subject to the same lockout screen; its simulated permission/recording and removal events never advance or invalidate real CloudKit metadata. The regular runtime creates one compatibility coordinator and one installation location owner and injects both into the model and real bootstrap.
The control record uses the private `WhereStoreCompatibility` zone and record type, with `requiredVersion` (Int64) and `accountID` (String).
Its `where-store-compatibility` zone subscription requests silent notifications. Notifications are advisory; foreground polling also refreshes the decision.

The Canadian subdivision release uses data version 2. Confirm these rollout steps
before distributing it to installations with synced history.

1. Use a recording-enabled validation build with Always permission to create the control record in the Development CloudKit environment.
2. Deploy its record schema to Production through CloudKit Console before distributing the cloud-enabled build.
3. Distribute the version-1 compatibility gate to all supported installations.
4. Update the recording device to the version-2 build so it can advance the shared version.
   A version-2 viewer waits while the shared version is 1. A version-1 reader that
   observes version 2 must update to reopen history.

Builds that predate the gate cannot obey it. A version increase does not make an existing unsupported build safe.
The protocol stops the entire session after detection. It does not make metadata and SwiftData synchronization atomic across devices.

Compatibility acceptance on two devices:

1. Keep one recording device on version 1. Install a version-2 validation build on a viewer and verify that it waits without opening history.
2. Install version 2 on the recording device. Verify that it publishes before opening history and that the viewer recovers.
3. Keep a version-1 device open during that publication. Verify that it hides history, stops GPS, and releases its scope.
4. Repeat through foreground entry, a control-record push, a remote import, and Retry after a network outage.
5. After successful verification, test offline relaunch on the same account and version. CloudKit must still resolve the account identity.
6. Test an unverified cloud upgrade, restricted/unavailable account, missing permission for publication, and malformed receipt. Each must remain blocked.
7. Sign out with compatible data and verify local recording, then sign in and verify that the old scope retires before CloudKit opens. Repeat with a higher cached version: signing out must not bypass the update requirement. Check Development share access after the app writes its local receipt.
7. During lockout, invoke an intent and save from the share sheet. Verify an actionable error and no new store open.
8. Restore network access and the matching version. Verify one fresh scope, preserved consent, and the retained location outbox.

The app target owns `iCloud.com.stuff.where`, the Push Notifications
entitlement, and the remote-notification background mode. Widgets and the share
extension intentionally have only the App Group entitlement: they write/read
local shared artifacts, while the app's single SwiftData container owns
CloudKit mirroring. Development uses `.localOnly`; exercise sync with
`./Where/install --cloudkit`, which keeps the isolated Development bundle and
App Group while selecting `.cloudKit`. Beta and App Store always select
`.cloudKit` with the production App Group. The installer compiles the
validation choice into that Development app, so manual, background, and
CloudKit-push relaunches keep using CloudKit until another build is installed
without `--cloudkit`.

Before shipping a schema change:

1. Run `./Where/install --cloudkit` (or install a Release build) against the Development CloudKit environment and open the store so SwiftData initializes the additive schema.
2. Inspect the new fields/record types in CloudKit Console, then deploy that schema to Production before distributing the build.
3. On two devices signed into the same iCloud account, open Settings → Devices and verify both generic hardware profiles arrive.
   Rename one and verify the nickname syncs.
4. On each device, toggle only its own Automatic Recording switch.
   Verify the local device starts or stops and its advisory status later updates on the other device without changing that other installation's switch.
5. Remove the secondary device from the carried device.
   Verify its earlier history remains visible, locations at and after the removal disappear, and the secondary device stops when it next syncs.
   Rejoin it and verify it gets a new identity with recording Off until explicitly enabled there.
6. Export a backup, then exercise Merge and Replace.
   Verify names and removals round-trip, neither strategy changes this installation's recording choice, and Replace discards pending pre-import locations before recording resumes.

On a fresh install, onboarding recommends automatic recording On for an iPhone only when no other device recently reported recording, and Off for an iPad/other device or explicit rejoin, then requires the user to confirm.
Existing installations created before that choice was introduced revisit only the final recording page once.
Enabling is the only path that asks for location access.
