# Launch lifecycle (narrow slice)

Models the undetermined → foreground promotion path in
[`LifecycleRunner`](../../../Shared/LifecycleKit/Sources/LifecycleRunner.swift)
and [`RootView`](../../WhereUI/Sources/RootView.swift): a headless drive runs
background-safe trunk steps, `enterForeground()` promotes the reason, and the
re-drive skips memoized steps while running foreground-only work.

## Correspondence

| Model | Production |
| --- | --- |
| `reason` | `LifecycleReason` (`.undetermined` / `.userForeground`) |
| `memoSyncAuth`, `memoReconcile` | `LifecycleRunner.memo` — completed step IDs |
| `captureTodayDone` | `CaptureTodayStep` (`.foreground` only) |
| `driveActive` | at most one in-flight `drive()` task |
| `EnterForeground` | `LifecycleRunner.enterForeground()` |

Background steps stand in for `sync-auth` and `reconcile-tracking`. the
foreground step stands in for `capture-today`. Gates, detached fan-out, and
teardown are out of scope for this narrow slice.

## Properties

- `SingleDrive` — one walk in flight at a time
- `MemoNoDoubleRun` — promotion re-drive skips completed background steps
- `UndeterminedNoCaptureToday` — foreground-only work waits for promotion
- `ForegroundCaptureBeforeReady` — promoted launch reaches ready only after
  capture-today runs

## Result

**Verified for these model bounds and assumptions** on `Current.cfg`.
`Broken.cfg` (promotion clears memo and re-runs background steps) falsifies
`MemoNoDoubleRun`.

Swift guards:

- [`WhereLaunchTests.undeterminedLaunchDefersForegroundStepsUntilPromoted`](../../WhereUI/Tests/WhereLaunchTests.swift)
- [`LifecycleRunnerTests.promotionSkipsNodesCompletedInTheHeadlessDrive`](../../../Shared/LifecycleKit/Tests/LifecycleRunnerTests.swift)
- [`LifecycleRunnerTests.undeterminedLaunchRunsBackgroundNodesThenPromotesToForeground`](../../../Shared/LifecycleKit/Tests/LifecycleRunnerTests.swift)

Broader launch state-machine rewrite remains tracked in [`Where/TODOs.md`](../../TODOs.md).

Run: `./tla-check LaunchLifecycle`
