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
