---
name: running-tests
description: Run the test suite with ./test. Pick the right tier. Manage the per-checkout simulator. Use when you run tests, pick test scope, debug simulator launch failures, or review snapshot diffs.
---

How to run tests in this repo. Read root [`AGENTS.md`](../../../AGENTS.md) for
always-on rules. **Use [`./test`](../../../test)**. Do not hand-roll `tuist test`
or `xcodebuild`. Run checks in proportion to the change.
Canonical flag list: `./test --help`. Rationale for `./test` over alternatives:
header comment in [`test`](../../../test).

## Documentation-only changes

Pure documentation or comment-only changes can skip `./test`. Skip
`./swiftformat --lint` when the changed files are outside the formatter's
scope. Record skipped checks and the reason in the commit or PR validation.

Do not classify a semantic change to configuration, scripts, generator inputs,
executable examples, or app-rendered copy as documentation-only. Run the
narrowest applicable checks below instead.

## Pick a tier

Pick the **narrowest tier that covers the change**:

| Tier | Command | When |
|------|---------|------|
| Affected | `./test` | Default — bundles touched by your diff against `origin/main` |
| One bundle | `./test WhereCoreTests` | You know exactly what you touched |
| Unit suite | `./test --all` | Change spans modules; before a wide commit |
| Image suite | `./test --snapshots` | Triggers below |
| Everything | `./test --everything` | All iOS unit and image bundles plus default host/architecture checks |

Examples:

- Edited `WhereCore` only → `./test` (or `./test WhereCoreTests` if you want to be explicit)
- Edited `WhereCore` + `WhereUI` → `./test` or `./test --all` before committing
- Changed a stylesheet token that renders → `./test --snapshots` (or `./test` if the graph already pulls snapshots in)

Compare against a ref other than `origin/main`: `./test --base REF`.

## Architecture and host checks

Every normal invocation runs the complete Bumper Bowling sequence first. Use
`./test --architecture-only` to run only the configuration validation, rule
tests, and architecture lint.

CI test jobs use `--skip-architecture` because the dedicated Bumper job owns
that sequence. Do not use this flag for normal local validation.

Affected and unit-capable scopes run the backup-upgrader regression. A scope
that contains only image bundles skips that host-side unit regression.

For retained scripts, also run the applicable direct and public-command tests
from [`Tools/README.md`](../../../Tools/README.md#testing).
Use `./shellcheck` for shell changes. `./test` does not replace these checks.

## Snapshots

**Opt-in, not part of "done" by default.** Run `./test --snapshots` when the
change touches a **view or its appearance**, a **stylesheet token**, a **string
that renders**, **`SnapshotKit` / `SnapshotKitTesting`**, or a **reference
image**. `./test` with no arguments already includes image bundles when the
dependency graph says they're affected.

- **`--review`** — how each differing reference differs (pixel count, max delta,
  changed region); use to tell a broken render from antialiasing drift
- **`--timings`** — where capture time went per phase
- **`--record MODE`** — re-record references: `all`, `failed`, `missing`, or
  `never` (default). Fix the view first; re-record only when the render is
  correct

Snapshot runs require the exact Xcode build in
[`.xcode-build-version`](../../../.xcode-build-version). `./test` rejects a
different selected build before project generation or simulator boot. Install
the pinned build. Then select it before you review or record references.

Do not parallelize the image suite. Simulators on one Mac share one render
server. That makes captures slower and flaky. See
[`Shared/SnapshotKitTesting/AGENTS.md`](../../../Shared/SnapshotKitTesting/AGENTS.md).

## Iterate faster

After a green build:

```bash
./test --no-generate --no-build WhereCoreTests
./test --only 'WhereCoreTests/FooTests/bar()'
```

`--only` takes a full xcodebuild test identifier — bundle, suite, or
`Bundle/Suite/testName()`. Repeatable for several tests.

Use `--no-build` only when the existing products include every change being validated.
After source or dependency changes, rebuild before claiming test coverage for them.
Use `--no-generate` only while project-generation inputs remain unchanged.

## When tests fail

- Swift Testing's headline is often contentless ("Issue recorded"). Read the
  **`↳` block** below it for the real reason, path, and snapshot paths.
- Snapshot mismatch → `./test --snapshots --review` on the failing reference.
- Async or race failure → control the relevant suspension and await the
  observable outcome. Do not replace the failure with an arbitrary sleep.
- Stable placeholder → use the fixture's readiness hook before measurement or
  capture. Pixel settling alone cannot prove async completion
  ([capture contract](../../../Shared/SnapshotKitTesting/AGENTS.md)).
- Green locally / red on CI → compare the provider's tested revision,
  toolchain, and selected suites through
  [`github-workflow`](../github-workflow/SKILL.md#merging-main-and-other-branches).
  Do not infer a branch conflict from a failing check alone.

Report the suites and test/image counts that actually ran. A successful build,
empty selection, or skipped test does not establish behavior coverage.

## Simulator

`./test` resolves a UDID via [`./simulator`](../../../simulator). Do not pass a
device *name* to `simctl`. Do not hand-roll a `-destination`.

- **First `./simulator` run in a checkout** creates and boots a device. Budget
  a couple of minutes for the first boot.
- **Launch failures that look like test failures** (suites that do run are
  green):
  - `Application failed preflight checks (Busy)`
  - `Mach error -308 — server died` / `crashed with signal kill before
    establishing connection`
  → wedged or contended device → `./simulator --recreate`, then re-run `./test`.
- Deeper ops (`--list`, `--prune`, `--device` / `--os`): `./simulator --help`.

Raw one-off `xcodebuild` (rare):

```bash
-destination "platform=iOS Simulator,id=$(./simulator)"
```

## Environment

- **macOS + Xcode required** for `./test`.
- **Linux cloud agents** — no simulator, no `./test`, no Swift toolchain. What
  does run: `./swiftformat --lint`, `./shellcheck`, `./attribution --check`,
  `mise exec -- ./sync-agents`, and the retained Python tool tests
  (`python3 -m unittest discover -s Tools/Tests -p 'test_*.py'`). See the Linux
  table in the root [`AGENTS.md`](../../../AGENTS.md#what-works-on-linux) for the
  three macOS-coupled carve-outs among those.

## Broad local iOS and macOS validation

```bash
mise install
./ide --no-open
./swiftformat --lint
./test --everything
# The native-macOS Ledger scheme has no simulator and runs in its own CI job:
mise exec -- tuist test Ledger-macOS-Tests --no-selective-testing -- \
  -destination 'platform=macOS'
```

This recipe is not the complete CI gate. Read
[GitHub Actions](../../../.github/workflows/ci.yml) for the format and retained-tool checks.
Read [CircleCI](../../../.circleci/config.yml) for audience builds and artifact/shard validation.
Select additional checks for the changed inputs rather than treating one green command as all CI coverage.
