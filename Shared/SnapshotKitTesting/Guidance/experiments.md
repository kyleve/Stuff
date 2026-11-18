# Snapshot pipeline measurements

## Three things measured and rejected — don't re-derive them

- **Sharding the suite across simulators on one Mac is 2.7x slower, and wrong.**
- **Measured 2026-07-28 on a 10-core / 24 GB machine: the serial suite runs in 142s** (twice, 142.2 and 142.1).
- **The same suite split into four duration-balanced slices across four booted simulators took 387s.** Each slice had its own process with its own `StuffTestHost`.
- **That sharded run produced 9 failures** (two settle timeouts, one image mismatch).
- **Separate processes fix the shared-state interleaving that sank the earlier in-process attempt.**
- **They do not fix the real constraint: every shard contends for one render server.**
- **Then `drawHierarchy` slows down enough to push captures past their settle budget.**
- **The bar for keeping sharding was a 30% win.**
- **Isolated CI runners avoid that contention.** PR #237 retired their duplicated setup/build cost after the M4 Pro migration made one serial job fast enough.
- **Do not reach for `-parallel-testing-enabled` either.** It distributes XCTest *classes*, and Swift Testing presents none.
- **Then it lands everything on one worker.** Swift Testing's own parallelism interleaves captures in a single host process (24+ spurious mismatches, 1.2-3x slower).
- **Quiescence cannot replace the pixel digest.**
- **`SNAPSHOT_SETTLE` selects `pixel` (default), `quiescence`, or `both`.** Quiescence uses a `beforeWaiting` run-loop observer plus a recursive `needsLayout`/`needsDisplay`/`animationKeys` walk.
- **`both` runs them together and reports disagreements.**
- **Run in `both` mode (2026-07-28) over 260 references of the time; current inventory is in [`MODULE_AUDIT.md`](../../../MODULE_AUDIT.md).** The counts below are that run's, not current.
- **That run had 226 settle phases, 134 with some disagreement.**
- **8 cases had quiescence declare settled *earlier* than the digest.** Every one was a `Loaded_*` case whose content arrives late.
- **That is the one dangerous direction.** It would capture a frame no reference recorded.
- **That is what `settleContent`'s doc comment predicts.** A SwiftUI update deep in the hosted tree never dirties the root.
- **Flags read after a commit has flushed look clean.**
- **Keep the mechanism so the experiment is re-runnable after a toolchain change.** It is not a candidate default.
- **Sample pending layout before the loop's own `layoutIfNeeded`.** Reading it afterwards makes that third of the signal vacuously clean.
- **Keep separate observed-change flags for the two mechanisms.** Then `both` genuinely leaves the verdict to the digest.
- **Sharing one flag let quiescence flapping return `.timedOut` for content the digest never saw change.** That alters the experiment's own result.
- **Guard: `SnapshotQuiescenceTests.staticContentSettlesRegardlessOfMechanism`.**
- **No public API sees pending dispatch or Swift-concurrency work.**
- **`CFRunLoopGetNextTimerFireDate` reports only `CFRunLoopTimer`s.** Then "is something scheduled to land in 200ms?" is unanswerable.
- **That is why the floors exist and why they need per-case seams.**
- **`CATransaction.addCommitHandler` is macOS-only and absent from the iOS SDK.** A commit-counting variant is not available either.

## Public UI update callbacks — 2026-11-17

A passive `UIUpdateLink(view:)` probe observed `.afterUpdateComplete` during
Calendar and MainTabs captures on Xcode/iOS 27.2, starting from `445375f86`.
All 124 captures passed with unchanged pixel settling and references.

Of 221 settling phases, all 188 detached phases received no callbacks. All 33
scene-backed phases received callbacks: the first arrived after a median 6.5ms,
while those phases settled after a median 570.2ms. The observer did not request
continuous updates and was disabled on every exit. The temporary probe was removed.

This hook cannot replace general snapshot settling. Detached synthetic windows
do not deliver it, and the public contract completes one UI update, not later
async work or native material adaptation. The timing gap alone does not identify
which later work remained. Application-owned content completion can still make
measurement ready before final pixel settling.

See the [experiment and implementation evidence](../../../Plans/2026-11-17-snapshot-completion-hooks/README.md)
and Apple's [update-phase contract](https://developer.apple.com/documentation/uikit/uiupdateactionphase/afterupdatecomplete).

## Render cost and synchronous sizing — 2026-11-17

At `2fd1cdfaa` on Xcode/iOS 27.2, a process-scoped Time Profiler trace found
color conversion in 1.740s of the 3.793s sampled CPU weight attributed to settle
image rendering. A separate wall-stack sample also found render-server waits.
These focused samples do not measure suite-wide CPU cost or prove buffer sizes.

Two controls and two extended-color intermediate runs each passed the same 110
captures. Extended color reduced mean traced rendering by 12.55% and settling
by 2.99%, but did not improve end-to-end time: the test phases averaged 134.044s
for the controls and 135.916s for the candidate. Faster samples produced more
passes before the unchanged floors. A renderer-reuse trial was within control
variation. Neither candidate became the default. These trials were local; a matched
CI trial remains open because slower CI samples can change the effect of the
unchanged floor. Sampling frequency is also untested here. Keep these limits
explicit when using this result to choose further work.

Both formats passed real hierarchy-render checks for color, transparency,
cumulative fading, a bottom-edge sample pixel, and fractional patches beside
wide-color content. Keep these guards in `SnapshotRenderingSupportTests`:
scripted drawing contexts and prebuilt sRGB images do not exercise UIKit's
compositing and downsampling path.

Synchronous data does not prove synchronous geometry. Skipping measurement
settling for Settings made all 16 variants too short: 156 pixels (52 points)
in ordinary variants and 219 pixels (73 points) at AX5. Their rendered content
had not established its final hosted size. Keep that measurement settle;
passing data-loading checks or observing no changes in later samples is
insufficient evidence to remove it.

The [controlled experiments](../../../Plans/2026-11-17-snapshot-settling-investigation/03-controlled-experiments.md)
retain the methods, raw-evidence locations, and accepted consumer-specific changes.

## Holding the measurement host through capture — 2026-11-18

Keeping one native mount through a full-content capture had little effect on 200 screens and comparison sheets while both settling policies stayed in place. Drawing immediately after measurement on eligible fixtures saved about 44 seconds. On the Flyover iPad list it also captured a loading indicator in place of a widget preview. The normal whole-image comparator accepted that image. Check asynchronous content at the final capture size before opting a fixture into an early draw. [Paired timings, exact selection and pixel evidence](../../../Plans/2026-11-18-requested-snapshot-frames/04-two-hundred-more.md)
