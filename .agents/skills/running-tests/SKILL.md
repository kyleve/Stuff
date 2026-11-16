---
name: running-tests
description: Select and run repository checks with ./test, or diagnose simulator and snapshot failures.
---

# Running tests

Use `./test` for iOS bundles. Its `--help` owns the flag list.

## Documentation-only changes

Pure documentation or comment-only changes can skip `./test`.
When changed files are in the formatter's scope, run `./swiftformat --lint`. Otherwise, skip it.
Record skipped checks and the reason in the commit or PR validation.

Configuration, scripts, generator inputs, executable examples, and app-rendered copy need checks for their actual effect.

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

Use `--base REF` for another diff base and `--only Bundle/Suite/testName()` for a focused selection.
Reuse products with `--no-build` only when they include every change being validated.
Use `--no-generate` only while project-generation inputs remain unchanged.

## Architecture and host checks

Normal invocations run Bumper Bowling first; `--architecture-only` selects it alone.
`--skip-architecture` is for CI jobs whose dedicated Bumper job owns that check.

Unit-capable scopes include the backup-upgrader regression. `--all` and `--everything` also include host-side `PeriscopeMacrosTests`; snapshot-only scopes include neither.
Use `--skip-host-tests` only when another invocation owns those checks. Artifact consumers and CircleCI delegates follow their CI configuration.

Tool changes also need the applicable [direct/public-command checks](../../../Tools/README.md#testing); shell changes use `./shellcheck`.

## Snapshots

Run image checks for view/appearance changes, rendered stylesheet tokens or strings, SnapshotKit/SnapshotKitTesting, or reference images.
The affected scope already selects image bundles through the dependency graph.
Read [snapshot validation](references/snapshots.md) when selecting, reviewing, or recording image coverage.

## When tests fail

Read Swift Testing's `↳` details, not only its “Issue recorded” headline.
For capture failures, use [snapshot validation](references/snapshots.md).
For launch failures or CI-only failures, use [failure diagnosis](references/failures.md).

## Simulator

`./test` owns destination selection through `./simulator`.
Use a UDID, never a device name, for necessary one-off `simctl` operations.
Read [failure diagnosis](references/failures.md#simulator-launch) only for simulator recovery.

## Environment

iOS bundles require macOS and Xcode. Use [Environments and CI](../../../.agents/references/environments.md#what-works-on-linux) for Linux checks.
Report the tested revision, suites, and actual test/image counts; builds and empty selections are not behavior coverage.
