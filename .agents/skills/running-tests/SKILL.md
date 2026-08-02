---
name: running-tests
description: Runs the test suite via ./test, picks the right tier, and manages the per-checkout simulator. Use when running tests, choosing a test scope, debugging simulator launch failures, or reviewing snapshot diffs.
---

How to run tests in this repo. Read root [`AGENTS.md`](../../../AGENTS.md) for
always-on rules: **use [`./test`](../../../test)** — never hand-roll `tuist test`
or `xcodebuild`; **`./swiftformat --lint` and `./test` are part of "done".**

## Quick start

```bash
./test              # default: affected bundles only
./test --help       # full flag list
```

`./test` resolves the scheme, gets a UDID from `./simulator`, and streams
progress. A bare `xcodebuild` lets the tool pick a device, which lands on the
machine-wide simulator every other checkout is also using, and the image suite
only compares correctly under the scheme carrying its `SNAPSHOT_EXPECTED_*` /
`TZ` pins.

## Test tiers

Pick the **narrowest tier that covers the change** — running everything by
reflex is what made a local check cost a coffee break:

| Tier | Command | When |
|------|---------|------|
| Affected | `./test` | The default. Runs only the bundles your working tree affects. |
| One bundle | `./test WhereCoreTests` | You know exactly what you touched. |
| Unit suite | `./test --all` | Before committing a change that spans modules. |
| Image suite | `./test --snapshots` | Only when the triggers below apply. |
| Everything | `./test --everything` | Full revalidation, and what CI runs. |

## Image snapshots

**The image suite is serial on purpose.** Splitting it across simulators was
measured and rejected — 2.7x slower plus spurious failures, because every shard
contends for one render server. The numbers and the two other dead ends are in
[`Shared/SnapshotKitTesting/AGENTS.md`](../../../Shared/SnapshotKitTesting/AGENTS.md);
read them before proposing parallelism here.

**The image suite is opt-in, not part of "done" by default.** It is the slow
half, and most changes cannot affect it. Run `./test --snapshots` when the
change touches a **view or its appearance** (a `WhereUI`/`BroadwayUI` view, a
stylesheet token, a string that renders), **`SnapshotKit` or
`SnapshotKitTesting`**, or **a reference image**. `./test` with no arguments
already picks the image bundles up when the dependency graph says they're
affected, so the explicit form is for when you want them *and* nothing else.

Two flags exist for reading a snapshot run rather than just passing it:
`./test --snapshots --timings` prints where capture time went per phase, and
`--review` prints how each differing reference differs — pixel count, max
channel delta, changed region — sorted by max delta, which is the column that
tells a broken render from antialiasing drift.

## Why not tuist test

**Scope is explicit, not inferred from a cache.** `./test` derives affected
bundles from the manifests (`swift package dump-package` plus `Project.swift`)
and passes `-only-testing` for them, so there is no `--no-selective-testing` to
remember — `--everything` is the "run it all" answer. Relying on Tuist's
selective testing would mean running `tuist test`, and the two reasons not to
are measured — see the header comment in [`test`](../../../test), which also
records how to re-verify them:

- **Its formatter swallows the failure reason, with no flag that recovers it.**
  Swift Testing's headline for a recorded issue is a contentless "Issue
  recorded" and the reason lives in the `↳` block after it, which xcbeautify
  drops — so a snapshot mismatch reached CI as "Recorded an issue" with no
  numbers, no path, and no image.
- **`-collect-test-diagnostics never` saves ~10 minutes per failing run.**
  Without it xcodebuild waits out a fixed 600-second diagnostics timeout before
  reporting: the same one-test failure took 28s through `./test` and 620s
  through `tuist test`.

Little is given up. Tuist's hash cache does work locally, but there is no Tuist
server, so on CI's fresh checkout it skips nothing — and "changed against
`origin/main`" is the better question for a PR than "changed since this
machine's last successful run".

## Per-checkout isolation

`./test` and `./profile` derive their temporary work directory from the
checkout's canonical path, just as `./simulator` derives a checkout-owned
device. Preserve that per-checkout isolation: parallel clones/worktrees must
never share logs, progress state, result bundles, or profiling DerivedData.
`TEST_WORKDIR` / `PROFILE_WORKDIR` are explicit CI overrides, not required for
ordinary local runs.

## Simulator — one device per checkout, addressed by UDID

**Every checkout owns a simulator of its own, and `./simulator` is the only
thing that hands one out.** A name is ambiguous (`simctl` matches by name
only, and a machine usually has an "iPhone 17" per installed runtime), and a
shared device is contended (parallel checkouts race each other booting,
installing, and erasing it). Both surface identically: `Application failed
preflight checks (Busy)`, or `Mach error -308 — server died` / `crashed with
signal kill before establishing connection` — launch failures that look like
test failures but aren't (the suites that do run are green). So always pass a
**UDID** to `simctl`, never a name, and get that UDID from `./simulator`:

```bash
-destination "platform=iOS Simulator,id=$(./simulator)"
```

`./test` does this for you; reach for the raw form only in a one-off
`xcodebuild` invocation.

It derives a device name from the checkout's path
(`Stuff-<folder>-<hash>-iPhone-17-27.0`), **creates that device the first time
it's asked** — a fresh device's first boot runs a data migration, so expect a
couple of minutes once per checkout — boots it, waits for the boot to *finish*
(`simctl bootstatus -b` — a condition, not a fixed sleep), and prints only the
UDID, so it composes into any destination. `./profile` and `./flaky` go through
it too, so a local repro targets a device nothing else can touch.

- It defaults to the CI pairing (iPhone 17 / iOS 27.0); `--device` / `--os`
  target another (each pairing is its own per-checkout device), and `--no-boot`
  just resolves the UDID. See `./simulator --help`.
- **Don't hand-create, rename, or reuse these devices.** The name is the
  ownership record; a duplicate reintroduces exactly the ambiguity above, and
  the script warns when it finds one.
- `--list` shows every managed device with the checkout that owns it, and
  `--recreate` replaces a wedged one. `--prune` deletes the devices whose
  checkout is gone — run it after deleting a worktree or clone, with
  `--dry-run` first if you want to see the plan. It skips a checkout whose
  *parent* directory is missing too, since an unmounted volume is
  indistinguishable from a deletion and a device takes everything installed on
  it to the grave.
- **Renaming or moving a checkout gives it a new device**, because the name is
  derived from the path. The old one turns up as `unowned` in `--list`;
  `--prune` reports it but won't delete it (a cleared index makes a live
  checkout's device look abandoned in exactly the same way), so clearing one is
  a deliberate `xcrun simctl delete <udid>`.
- Never reintroduce a `name=…` destination or a bare `simctl <name>` call in a
  script. If you *do* keep a name-based `-destination` by hand, always include
  `OS=` so *xcodebuild* resolves unambiguously — that disambiguates the test
  destination only, not any `simctl` command alongside it. Doing it by hand
  also means remembering that `simctl shutdown` is async: poll until the
  device actually reads `(Shutdown)` before `erase`/`boot`.

**CI takes the one exception, and still resolves by UDID.** A job owns its
VM, so the boot step passes `--shared` (the image's existing iPhone 17,
skipping a per-run first boot) — but it still resolves the UDID,
`bootstatus -b`s it, and passes `-destination "…,id=$UDID"` under a
`timeout-minutes` cap: a cold or wedged CoreSimulator has stretched the
~10-minute test job to **3.5–5 hours** (runs on 2026-07-23). See
[`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml).

## Full macOS validation (matches CI)

```bash
mise install
./ide --no-open
./swiftformat --lint
./test --everything
```

The first `./simulator` run in a checkout creates that checkout's device, so
budget a couple of minutes for it; CI adds `--shared` because a job's VM is
already isolated.
