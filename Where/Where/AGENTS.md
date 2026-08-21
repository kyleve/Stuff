# Where (app target) – Module Shape

The **Where** iOS app target is the process's composition root and nothing else.
`AppDelegate` selects one process-lifetime `WhereApplicationRuntime`.
`RegularApplicationRuntime` owns the shipping stack. The DEBUG-only
`WhereInspectorApplicationRuntime` owns the alternate Inspector stack. See
[`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first. They own build/format,
layering, and the domain rules this target merely starts up.

## Scope

- **Keep it tiny.** Domain behavior goes in `WhereCore`. Presentation goes in
  `WhereUI`. If a change here is more than wiring, it belongs in a module. The
  target is a Tuist `.app` ([`Project.swift`](../../Project.swift)); its bundle
  ID, Info.plist keys, entitlements, build settings, and audience schemes live
  in that manifest — there is no checked-in plist to edit.
- `Scripts/` holds this target's build-phase scripts, not dev commands (those
  are the repo-root executables). Today that is
  [`stamp-build-info.sh`](Scripts/stamp-build-info.sh). It stamps the commit
  and the Swift compiler settings into the built Info.plist. See [Version and
  build metadata](../../AGENTS.md#version-and-build-metadata) for the
  constraints on it.
- `Resources/AppIcon.xcassets` is managed by `./icons` (see the root
  [`AGENTS.md`](../../AGENTS.md#managing-app-icons)). Never hand-edit it.
- `Resources/attribution.json` is the app's generated attribution report.
  `attribution-sources.json` at this module's root declares where it reads
  from. Both are `./attribution`'s
  ([Attribution](../../AGENTS.md#attribution)). Never hand-edit the report.
  Only this bundle carries one. `AppAttributionTests` lives in this
  target's test bundle (the one hosted by `Where.app`, where `Bundle.main` is
  the shipping bundle). `./attribution --check` in CI covers the report still
  matching the dependency graph, which no test bundle can see.

## Invariants

- **Select exactly one runtime in `AppDelegate.init`.** The delegate and
  `WhereApp` forward through `WhereApplicationRuntime`. Never add mode switches
  to lifecycle callbacks, `RootView`, or feature code. In DEBUG, finish
  Inspector's latched store-family recovery before constructing that runtime.
- **Resolve `WhereBuildEnvironment.current` once in `AppDelegate.init`.** Its
  audience condition must match the generated Info.plist, and the selected App
  Group, storage policy, widget refresher, App Intents handoff, and primary icon
  must be injected from that one value.
- **Release always builds `RegularApplicationRuntime`.** Boot preference reads,
  Inspector configuration, and menu integration stay under `#if DEBUG`.
- **Wire regular launch in `didFinishLaunching`, not a SwiftUI `.task`.** When
  CoreLocation relaunches the app after termination there is no UI. A view's
  `.task` is not a reliable hook. `didFinishLaunching` always runs. The regular
  runtime builds the `LifecycleRunner` (whose synchronous
  `initializePrerequisites` installs the `CLLocationManager` in time to receive
  the queued event). It hands it to `RootView` through `WhereApp`. Do not move
  this wiring into a view.
- **Reconcile reporting before forwarding launch to the selected runtime.**
  Snapshot crash and replay choices once. Use the same process preferences for
  `WhereModel`. Never start the provider on an all-Off launch. Remote-log sink
  removal must drain before sleeping. A newly applied live policy uses a
  choice-time cutoff, so queued earlier records are not exported retroactively.
  Keep performance tracing separate.
- **The regular runtime owns exactly one of each shared thing** — one
  `FileInstallationRecordingContextStore`, one `WhereModel`, one
  `IntentServices`, one launcher. Create them here and inject down, per
  [Composition](../../AGENTS.md#composition-create-once-inject-down). The
  launch's `resolve-scope` step is the process's only store open. It runs
  *behind* the onboarding gate. This target opens nothing at startup. The
  intents stack derives from whatever scope the launch resolves, in the
  `onServicesReady` hook.
- **Only the app owns the CloudKit capability.** Keep its App Group, CloudKit
  container (`iCloud.com.stuff.where`), Push Notifications entitlement, and
  remote-notification background mode together in `Project.swift`; widgets and
  the share extension stay App Group-only and never open a CloudKit container.
- **Choose the regular runtime's store explicitly.** Beta and App Store use
  `.cloudKit`; Development uses `.localOnly` unless built with
  `WHERE_CLOUDKIT_VALIDATION` (`./Where/install --cloudkit`); the choice must
  survive every process relaunch.
- **Nothing here may assume the user has a store.** `didFinishLaunching` starts
  the ambient log sources and drives the launch. Anything wanting the user's
  data waits for `.ready` and checks what it got. The Spotlight indexing after
  `launcher.run()` skips a demo session. Demo data must not reach an index that
  outlives the process. See [Scopes and the
  launch](../AGENTS.md#scopes-and-the-launch).
- **Register the App Intents dependency before anything async.** The
  `AppDependencyManager.shared.add(...)` call must stay at the top of
  `didFinishLaunching`. Then `@Dependency` always resolves once the system starts
  delivering intents.
- **The app launches `.undetermined`.** Under the UIScene lifecycle
  `applicationState` reads `.background` here even for a user tap. The reason
  stays honest until `RootView`'s `enterForeground()` promotes it. Do not
  substitute a guessed `.background(cause)` or `.userForeground`.
- **`WhereShortcuts` lives here on purpose.** App Intents metadata extraction
  discovers phrases reliably from the main bundle. That is why the provider
  is not in `WhereIntents` (whose types are `public` so this file can reference
  them). Every phrase must contain `\(.applicationName)`.

## Testing

`WhereTests` is the one bundle hosted by the **Where app itself** rather than
`StuffTestHost`. The host's own launch has already run, including the
intent-services registration. Inject runtime spies without launching a second
regular runtime. Tests may construct an `AppDelegate(runtime:)` only with such
a spy. A second `RegularApplicationRuntime.didFinishLaunching` would
re-register the handoff, whose behavior is undocumented.
