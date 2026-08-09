---
name: running-tests
description: Run the test suite with ./test. Pick the right tier. Manage the per-checkout simulator. Use when you run tests, pick scope, debug simulator launch failures, or review snapshot diffs.
---

This skill tells you how to run tests in this repo. Read root [`AGENTS.md`](../../../AGENTS.md) for always-on rules. Use [`./test`](../../../test). Do not hand-roll `tuist test` or `xcodebuild`. Validate in proportion to the change. The canonical flag list is `./test --help`. The header comment in [`test`](../../../test) explains why `./test` is the entry point.

## Documentation-only changes

You may skip `./test` for pure documentation or comment-only changes. You may skip `./swiftformat --lint` when changed files are outside the formatter scope. Record skipped checks and the reason in the commit or PR validation.

Do not classify a semantic change to configuration, scripts, generator inputs, executable examples, or app-rendered copy as documentation-only. Run the narrowest applicable checks below instead.

## Pick a tier

Pick the narrowest tier that covers the change:

| Tier | Command | When |
|------|---------|------|
| Affected | `./test` | Default — bundles touched by your diff against `origin/main` |
| One bundle | `./test WhereCoreTests` | You know exactly what you touched |
| Unit suite | `./test --all` | Change spans modules; before a wide commit |
| Image suite | `./test --snapshots` | Triggers below |
| Everything | `./test --everything` | Full revalidation; what CI runs |

Examples:

- Edited `WhereCore` only → `./test` (or `./test WhereCoreTests` if you want to be explicit)
- Edited `WhereCore` + `WhereUI` → `./test` or `./test --all` before committing
- Changed a stylesheet token that renders → `./test --snapshots` (or `./test` if the graph already pulls snapshots in)

To compare against a ref other than `origin/main`, run `./test --base REF`.

## Snapshots

Snapshots are opt-in. They are not part of "done" by default. Run `./test --snapshots` when the change touches a view or its appearance, a stylesheet token, a string that renders, `SnapshotKit` / `SnapshotKitTesting`, or a reference image. `./test` with no arguments already includes image bundles when the dependency graph says they are affected.

- **`--review`** — how each differing reference differs (pixel count, max delta, changed region). Use it to tell a broken render from antialiasing drift.
- **`--timings`** — where capture time went per phase
- **`--record MODE`** — re-record references: `all`, `failed`, `missing`, or `never` (default). Fix the view first. Re-record only when the render is correct.

Do not parallelize the image suite. See [`Shared/SnapshotKitTesting/AGENTS.md`](../../../Shared/SnapshotKitTesting/AGENTS.md).

## Iterate faster

After a green build:

```bash
./test --no-generate --no-build WhereCoreTests
./test --only 'WhereCoreTests/FooTests/bar()'
```

`--only` takes a full xcodebuild test identifier — bundle, suite, or `Bundle/Suite/testName()`. Repeat it for several tests.

## When tests fail

- Swift Testing's headline is often contentless ("Issue recorded"). Read the **`↳` block** below it for the real reason, path, and snapshot paths.
- If a snapshot mismatches, run `./test --snapshots --review` on the failing reference.
- If tests are green locally and red on CI, merge latest `main` and re-run before you debug. See [`github-workflow`](../github-workflow/SKILL.md).

## Simulator

`./test` resolves a UDID via [`./simulator`](../../../simulator). Do not pass a device *name* to `simctl`. Do not hand-roll a `-destination`.

- The first `./simulator` run in a checkout creates and boots a device. Budget a couple of minutes for the first boot.
- Launch failures can look like test failures when suites that do run are green:
  - `Application failed preflight checks (Busy)`
  - `Mach error -308 — server died` / `crashed with signal kill before establishing connection`
  - If you see these errors, run `./simulator --recreate`. Then re-run `./test`.
- For deeper ops (`--list`, `--prune`, `--device` / `--os`), run `./simulator --help`.

Raw one-off `xcodebuild` (rare):

```bash
-destination "platform=iOS Simulator,id=$(./simulator)"
```

## Environment

- `./test` requires macOS and Xcode.
- Linux cloud agents can run `./swiftformat --lint` and `./sync-agents` only. They cannot run the simulator or tests. Full validation matches CI on macOS.

## Full macOS validation (matches CI)

```bash
mise install
./ide --no-open
./swiftformat --lint
./test --everything
# The native-macOS Ledger scheme has no simulator and runs in its own CI job:
mise exec -- tuist test Ledger-macOS-Tests --no-selective-testing -- \
  -destination 'platform=macOS'
```
