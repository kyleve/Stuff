# Where (app target) – Module Shape

The **Where** iOS app target: the process's composition root and nothing else.
Three files — `WhereApp` (`@main`), `AppDelegate` (the wiring), and
`WhereShortcuts` (the App Shortcuts phrases). See [`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md) — read those first; they own build/format,
layering, and the domain rules this target merely starts up.

## Scope

- **Keep it tiny.** Domain behavior goes in `WhereCore`, presentation in
  `WhereUI`. If a change here is more than wiring, it belongs in a module. The
  target is a Tuist `.app` ([`Project.swift`](../../Project.swift), bundle ID
  `com.stuff.where`), and its Info.plist keys, entitlements, and build settings
  live in that manifest — there is no checked-in plist to edit.
- `Scripts/` holds this target's build-phase scripts, not dev commands (those
  are the repo-root executables). Today that is
  [`stamp-build-info.sh`](Scripts/stamp-build-info.sh), which stamps the commit
  into the built Info.plist — see [Version and build
  metadata](../../AGENTS.md#version-and-build-metadata) for the constraints on
  it.
- `Resources/AppIcon.xcassets` is managed by `./icons` (see the root
  [`AGENTS.md`](../../AGENTS.md#managing-app-icons)) — never hand-edit it.
- `Resources/attribution.json` is the app's generated attribution report;
  `attribution-sources.json` at this module's root declares where it reads
  from. Both are `./attribution`'s
  ([Attribution](../../AGENTS.md#attribution)) — never hand-edit the report.
  Only this bundle carries one, so `AppAttributionTests` lives in this
  target's test bundle (the one hosted by `Where.app`, where `Bundle.main` is
  the shipping bundle); `./attribution --check` in CI covers the report still
  matching the dependency graph, which no test bundle can see.

## Invariants

- **Launch is wired in `didFinishLaunching`, not a SwiftUI `.task`.** When
  CoreLocation relaunches the app after termination there is no UI, so a view's
  `.task` is not a reliable hook; `didFinishLaunching` always runs. It builds
  the `LifecycleRunner` (whose synchronous `initializePrerequisites` installs
  the `CLLocationManager` in time to receive the queued event) and hands it to
  `RootView` through `WhereApp`. Don't move this wiring into a view.
- **This target owns exactly one of each shared thing** — one `WhereModel`, one
  `IntentServices`, one launcher — created here and injected down, per
  [Composition](../../AGENTS.md#composition-create-once-inject-down). The
  launch's `resolve-scope` step is the process's only store open and runs
  *behind* the onboarding gate, so this target opens nothing at startup; the
  intents stack derives from whatever scope the launch resolves, in the
  `onServicesReady` hook.
- **Nothing here may assume the user has a store.** `didFinishLaunching` starts
  the ambient log sources and drives the launch; anything wanting the user's
  data waits for `.ready` and checks what it got — the Spotlight indexing after
  `launcher.run()` skips a demo session, whose data must not reach an index that
  outlives the process. See [Scopes and the
  launch](../AGENTS.md#scopes-and-the-launch).
- **Register the App Intents dependency before anything async.** The
  `AppDependencyManager.shared.add(...)` call must stay at the top of
  `didFinishLaunching` so `@Dependency` always resolves once the system starts
  delivering intents.
- **The app launches `.undetermined`.** Under the UIScene lifecycle
  `applicationState` reads `.background` here even for a user tap, so the
  reason stays honest until `RootView`'s `enterForeground()` promotes it. Don't
  substitute a guessed `.background(cause)` or `.userForeground`.
- **`WhereShortcuts` lives here on purpose** — App Intents metadata extraction
  discovers phrases reliably from the main bundle, which is why the provider
  isn't in `WhereIntents` (whose types are `public` so this file can reference
  them). Every phrase must contain `\(.applicationName)`.

## Testing

`WhereTests` is the one bundle hosted by the **Where app itself** rather than
`StuffTestHost`, so the host's own launch has already run — including the
intent-services registration. Keep it to shell-wiring smoke tests, and **don't
construct additional `AppDelegate`s**: each `didFinishLaunching` re-registers
the handoff, and `AppDependencyManager`'s re-registration behavior is
undocumented (see [`WhereIntents/AGENTS.md`](../WhereIntents/AGENTS.md#testing)
for why intent `perform()` is untestable here).
