# Scope and launch contracts

## Scopes and the launch

- Verify data compatibility before onboarding discovery, interrupted import recovery, or production scope construction.
  Keep the compatibility gate active for foreground and headless launches. Local-only and demo worlds bypass CloudKit verification.
  A live lockout stops recording and retires the whole scope. Guards: `WhereCompatibilityModelTests` and `WhereLaunchTests`.

- **A `WhereScope` is what the app is logged in *to*.** It is one open store's
  `WhereServices`, the `WherePreferences` driving it, and the durable log store
  they record into. It is created whole. `WhereSession` is built from one. A
  surface must not read one world's store against another's preferences.
- **Onboarding may prepare the real store only for recording-authority
  discovery.** Retain that exact store for scope resolution. Do not construct
  services, expose App Intents, start GPS, or open the log store until the
  user finishes choosing a world.
- **At most one scope is active and log-routing at a time.** Logging out — a
  reset, or leaving a demo — releases and tears down the scope. Logging back in
  builds a fresh one. Flyover is the narrow exception to "one open world". It
  may retain one separately built, in-memory demo scope beside the active app
  scope. It never activates or log-routes it. It never opens a second copy of
  the real store. Guards:
  `WhereResetTests.loggingOutReleasesTheScopeBeforeTheNextLoginOpensOne`.
  `WhereFlyoverWorldTests.buildsASeededSiblingWithoutActivatingIt`.
- **The onboarding gate declares `modes: .all`,** not the `.foreground`
  default. Parking a headless launch is the point. Keep recording confirmation
  in the backup-excluded installation sidecar. Then restoring backed-up
  `hasOnboarded` onto another device parks at the final choice page.
- **A gate carries no value.** A choice made *at* it reaches `resolve-scope`
  through `WhereModel`. That is the one step that reads model state rather than
  the trunk.
- **Ambient log sources start at process launch. The durable sink is a
  scope's.** Records emitted before a scope exists reach OSLog only.
- **Publish durable-log bring-up through `WhereModel.logStoreState`.** The
  active scope owns the store. The process model mirrors opening, ready,
  unavailable, and failed states for the DEBUG developer surface. Guards:
  `WhereModelTests`.

### Demo mode

- **Demo mode is a second scope, not a flag.** It uses an in-memory store
  seeded by `DemoDataBuilder`, in-memory preferences and log store, noop
  schedulers, outbox, and widget refresher. Enter from the onboarding intro.
  Leave from the first block of Settings (`WhereLaunch.exitDemoPlan`). Quitting
  mid-demo needs no teardown.
- **A demo leaves no mark on the device.** Anything that writes outside its own
  store is injected as a no-op or skipped at the call site (Spotlight indexing
  in `AppDelegate`). Settings hides the groups that would reach past it
  (`SettingsDestination.isAvailableInDemoMode`). A new persisting surface needs
  the same treatment.
- **`WhereModel` decides when a scope routes its logs.** A scope holds its log
  store from birth and routes only while active. One that opens while shadowed
  is remembered rather than attached. Guard:
  `DemoModeTests.aLogStoreOpeningLateNeverAttachesToAShadowedScope`.
- **Flyover builds but never activates its demo scope.** Its frames share that
  one in-memory world while the real app keeps its current scope. Dismissing
  Flyover releases the sibling. The process-global `WhereLog` facade remains a
  known exception tracked in [Where backlog](https://linear.app/kve/view/1cdf347a9c54).
- **The logging system is injected, not global.** `WhereModel.logSystem` has no
  default. A test must not silently attach sinks to `Periscope.shared`. (The
  `WhereLog` facade still emits into `.shared`. Pre-existing.)
- **Demo mode asks for no permission and presents a granted user.** The
  scripted location source reports `.always`. The noop schedulers are built
  `authorized: true`. No surface nags about a permission the demo cannot obtain.
  Guard: `DemoModeTests.demoPresentsAFullyGrantedUser`.
- **Views branch on `\.isInDemoMode`.** Seed once at `RootView` via
  `demoMode(of:)`. Guard: `DemoModeEnvironmentTests`.
- App Intents answer from the demo store while it is active. That is
  process-scoped and self-correcting on exit. It is accepted rather than
  special-cased (#150).
