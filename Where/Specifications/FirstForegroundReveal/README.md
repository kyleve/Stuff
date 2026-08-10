# First foreground reveal

This model checks one narrow question: when a mounted, ready, headless Where
launch becomes foreground-visible, must the splash cover the first main-UI
reveal and then release, whether SwiftUI renders the runner's intervening
launching phase or coalesces directly to ready, without replaying on ordinary
scene resumes?

The model represents production source at commit
`9587d79f10af43a0a31fa61a235682845680a794`. It is design evidence for the
stated bounds and assumptions, not proof that SwiftUI or the implementation is
correct. Changes to `RootView` foreground promotion, `LifecycleRunner` phase
publication, `LifecycleContainer`'s observation/task identities, or
`LifecycleReadyRevealState` invalidate the result until this mapping is checked
again.

## Source correspondence

| Model state or action | Production counterpart |
| --- | --- |
| `reason` | `LifecycleReason.buildsNoViewTree`; headless until `enterForeground()` changes the reason to `.userForeground` |
| `runnerPhase` | The `.launching` and `.ready` surfaces published by `LifecycleRunner.drive(reason:)` |
| `BeginPromotion` | `RootView`'s active-scene entry into `LifecycleRunner.enterForeground()`, through the synchronous reason/launching publication before its first suspension |
| `CompletePromotion` | The replacement foreground drive publishing `.ready`; `Render` may or may not interleave before it |
| `dirty` / `Render` | A pending SwiftUI update and one evaluation of `LifecycleContainer.body` |
| `installedTaskKey` | The identity installed by `.task(id: isReadyAndVisible)` |
| `readyTaskPending` / `StartReadyTask` | The scheduled `.task` body through `readyBecameVisible` and capture of the current hold deadline |
| `splashObserved` | The last value observed by `.onChange(of: isShowingSplash)`; the callback reads the runner surface, not the displayed overlay |
| `revealState` | `LifecycleReadyRevealState` (`awaitingFirstVisibleReady`, `holdingSplash`, `revealed`) |
| `holdEpoch` / `sleepingEpoch` | Abstract identities for `splashHoldDeadline` and the deadline captured across `Task.sleep` |
| `TimerExpires` | Return from `Task.sleep` plus the cancellation/deadline-equality guards before setting `.revealed` |
| `renderedSurface` | No tree, the splash overlay, or revealed ready content selected by `LifecycleContainer` |
| `contentBuilt` | Ready content's single call site, built under the covering splash before reveal |
| `OrdinaryResume` | Later scene background/active cycles after promotion; the launch reason and ready phase stay unchanged |

The source entry points represented are `RootView.body`'s initial active-scene
task and `scenePhase` change handler, `LifecycleRunner.enterForeground()`, and
`LifecycleContainer.body`'s `onChange` and keyed task. The runner and reveal
state execute on the main actor. `enterForeground()` splits where it awaits its
replacement drive; the reveal task splits at `Task.sleep`. The synchronous
`onChange` callback is atomic with its modeled render because it has no
suspension at which another main-actor action can interleave.

## Properties

- `TypeOK` checks every model variable.
- `HeadlessBuildsNoTree` keeps a ready background launch viewless.
- `ContentRequiresReadyReveal` prevents content from becoming visible without
  both a foreground-ready runner and a released presentation state.
- `FirstRevealWasCovered` requires an observed splash before the first content
  reveal, including on a coalesced promotion.
- `CoveredReadyBuildsContent` requires ready content to warm beneath the splash.
- `OneHoldPerFirstReveal` prevents the ready transition or displayed overlay
  from replacing the first episode's original deadline.
- `NoStrandedReady` rejects a foreground-ready splash with no pending callback
  or timer capable of releasing it.
- `NoResumeReplay` keeps the revealed state and single content reveal across
  ordinary scene resumes.
- `EventuallyFirstReveal` requires a completed foreground promotion to finish
  its first reveal.

Weak fairness assumes an admitted foreground drive eventually completes,
SwiftUI eventually renders a dirty mounted view, an installed task eventually
begins, and a non-cancelled positive-duration timer eventually returns. No
fairness forces a background launch to become foreground-visible or a user to
perform an ordinary resume. These are the runtime progress guarantees needed
for `EventuallyFirstReveal`; the safety invariants do not depend on fairness.

## Bounds and exclusions

The model begins after a background-safe drive has reached `.ready` while its
container is mounted headlessly. The positive 800 ms minimum is abstracted to
one timer completion; the model preserves deadline identity and supersession,
not elapsed time. The current configurations cover one and two ordinary resume
cycles with an arm bound of two. Promotion ordering is nondeterministic, so TLC
explores both a rendered launching splash and a coalesced direct-to-ready
render. Explicit reachability cases make those branches and the two-resume path
non-vacuous.

Zero-duration policy, `.phaseDriven`, gates, failures, teardown/reset splash
episodes, animation frames, accessibility/hit testing, scene destruction and
recreation, multiple windows, process termination, and actual SwiftUI runtime
scheduling are excluded. The hosted Swift test remains the implementation
guard for the scheduling behavior represented by the model.

## Controls and result

The `readinessOnly` negative control keys the task only on the runner's ready
phase. TLC violates `NoStrandedReady`: the headless runner begins ready, the
foreground drive publishes splash and ready before a render, and the ready-only
identity therefore stays true. The coalesced ready render warms content beneath
the splash but schedules no callback or timer that can release it. The trace is
5 generated / 5 distinct states at depth 4.

The `selfRearming` negative control lets a held displayed overlay count as a
new splash appearance. TLC violates `OneHoldPerFirstReveal`: after a coalesced
promotion schedules the ready task, that task arms epoch 1, then the overlay
replaces it with epoch 2 while the only sleeping task still carries epoch 1.
The trace is 14 generated / 11 distinct states at depth 6.

The render-order reachability controls also fail as expected: TLC reaches a
coalesced promotion after 3 generated / 3 distinct states at depth 3, and a
rendered runner splash after 4 generated / 4 distinct states at depth 3. A
third control requires the configured two-resume path; its exact trace result
reaches both resumes after 26 generated / 17 distinct states at depth 9. These
traces demonstrate that the named paths are present rather than vacuously
hidden from the checked properties.

**Verified for these model bounds and assumptions.** TLC exhausts both current
configurations without an invariant, temporal-property, or deadlock error:

| Configuration | Ordinary resumes | Generated / distinct states | Depth |
| --- | ---: | ---: | ---: |
| `Current.cfg` | 1 | 31 / 18 | 10 |
| `CurrentRepeated.cfg` | 2 | 41 / 22 | 11 |

The deterministic software guard is
[`LifecycleContainerTests.promotedBackgroundReadyForcesTheFirstRevealSplash`](../../../Shared/LifecycleKitUI/Tests/LifecycleContainerTests.swift).
It mounts a ready runner headlessly, changes only its observed reason, then
asserts that content warms beneath a splash which eventually releases. Its
mutation control fails when the production task identity is reduced to
readiness alone.

## Run it

From the repository root:

```sh
./tla-check FirstForegroundReveal
```

The checker pins the tla2tools 1.7.4 release (TLC2 2.19, revision `5a47802`) at
SHA-256
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`
and Eclipse Temurin 21.0.8+9 through `mise`. It keeps downloads and run
artifacts under ignored `.build/tla/` and is not wired into CI.
