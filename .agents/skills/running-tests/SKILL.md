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

Pure documentation or comment-only changes can skip `./test`.
When changed files are in the formatter's scope, run `./swiftformat --lint`. Otherwise, skip it.
Record skipped checks and the reason in the commit or PR validation.

Do not classify a semantic change to configuration, scripts, generator inputs,
executable examples, or app-rendered copy as documentation-only. Run the
narrowest applicable checks below instead.

## Pick a tier

Pick the **narrowest tier that covers the change**:

| Tier | Command | When |
|------|---------|------|
| Affected | `./test` | Default — bundles touched by your diff against `origin/main` |
| One bundle | `./test WhereCoreTests` | You know exactly what you touched |
| Selected suites | `./test --only Bundle/Suite` | Focused behavior or coverage changes; repeat `--only` for each affected suite |
| Unit suite | `./test --all` | Shared behavior or integration risk spans the unit bundles |
| Image suite | `./test --snapshots` | Shared renderer or appearance changes affect image coverage across modules |
| Everything | `./test --everything` | All iOS unit and image bundles plus default host/architecture checks |

Examples:

- Edited `WhereCore` only → `./test` (or `./test WhereCoreTests` if you want to be explicit)
- Edited `WhereCore` + `WhereUI` → `./test`; use `--all` for integration risks beyond the affected selection
- Changed a component stylesheet token → its snapshot suite and relevant screen integration suites through `--only`
- Changed a shared renderer or system-wide appearance → `./test --snapshots`

Compare against a ref other than `origin/main`: `./test --base REF`.

## Architecture and host checks

Every normal invocation runs the complete Bumper Bowling sequence first. Use
`./test --architecture-only` to run only the configuration validation, rule
tests, and architecture lint.

CI test jobs use `--skip-architecture` because the dedicated Bumper job owns
that sequence. Do not use this flag for normal local validation.

Affected and unit-capable scopes run the backup-upgrader regression. A scope
that contains only image bundles skips that host-side unit regression.

`./test PeriscopeMacrosTests` runs the host-side macro suite without a simulator.
`./test --all` and `./test --everything` include it. `./test --snapshots` alone does not.

When another invocation owns the attribution, backup-upgrader, and macro tests, you can use `--skip-host-tests`.
CircleCI delegates these checks to the required GitHub macOS job. Artifact consumers also skip host checks.
Normal local runs retain their default checks.

For retained scripts, also run the applicable direct and public-command tests
from [`Tools/README.md`](../../../Tools/README.md#testing).
Use `./shellcheck` for shell changes. `./test` does not replace these checks.

## Snapshots

Run affected snapshot suites for changes to rendered views, stylesheet tokens, displayed strings, or reference images.
Use `./test --snapshots --only Bundle/Suite` for the owning component and relevant integration suites.
Changes to SnapshotKit configuration or capture code need their regression suites and affected rendering coverage.
Reserve the full image suite for changes whose effects span the shared renderer or application appearance.
Documentation-only edits and test deletions do not automatically require every image bundle.
`./test` with no arguments includes image bundles selected by the dependency graph.

- **`--review`** — how each differing reference differs (pixel count, max delta,
  changed region); use to tell a broken render from antialiasing drift
- **`--timings`** — where capture time went per phase
- **`--record MODE`** — re-record references: `all`, `failed`, `missing`, or
  `never` (default). Fix the view first; re-record only when the render is
  correct

Snapshot runs require the Xcode major.minor version in
[`.xcode-version`](../../../.xcode-version). `./test` rejects a
different major.minor version before project generation or simulator boot. Install
the pinned version. Then select it before you review or record references.

For component comparison sheets, run the component suites plus selected screen
integration suites. Inspect every theme panel at light/dark and relevant accessibility
sizes. Review the sheet PNG before recording. Its embedded panel map is part of the
reference; preserve PNG metadata. Missing, invalid, or changed panel maps fail.
A panel regression must fail at its own pixel-area budget even when the complete sheet would pass. Use `--timings`
to compare actual panel capture counts and runtime; composing panels does not avoid
rendering them. Preserve ungrouped reference paths and nest special traits inside
explicit theme groups. Follow the framework and consumer module `AGENTS.md` for
which cases belong in comparison sheets versus full screens.

For matrix reductions, compare retained case/configuration identities with the
remaining references. Use `--record never` for unchanged captures so a reduction
cannot bless an unrelated visual change. Record new or intentionally reframed
subjects in a separate focused run and inspect them before the final assertion run.

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
  [`github-workflow`](../github-workflow/references/merging.md#merging-main-and-other-branches).
  Do not infer a branch conflict from a failing check alone.

Report the suites and test/image counts that actually ran. A successful build,
empty selection, or skipped test does not establish behavior coverage.

## Simulator

Development commands default to the iOS 27.2 Simulator runtime.

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
  table in [Environments and CI](../../../.agents/references/environments.md#what-works-on-linux) for the
  three macOS-coupled carve-outs among those.

## Broad local iOS and macOS validation

```bash
mise install
./ide --no-open
./swiftformat --lint
./test --everything
```

This recipe is not the complete CI gate. Read
[GitHub Actions](../../../.github/workflows/ci.yml) for the format and retained-tool checks.
Read [CircleCI](../../../.circleci/continue.yml) for audience builds and artifact/shard validation.
Select additional checks for the changed inputs rather than treating one green command as all CI coverage.
