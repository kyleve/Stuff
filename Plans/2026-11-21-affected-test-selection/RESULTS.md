# Local test-selection experiment

Four of six representative PRs skip 15–23 of the 28 logical iOS test bundles.
The two remaining PRs select everything because their diffs include inputs without a safe dependency mapping.
This supports using the improved local selector and measuring actual runtime before changing CI.

## Method

Verified on 2026-11-21 with selector commit `d3955cb2652ddfaac117882db330357170bd15ad` from [PR #555](https://github.com/kyleve/Stuff/pull/555).
The package and project graph are unchanged from main `ddb0a85466d0ca8ee65e830a43f096e2fb72738e`: 22 ordinary bundles and six image bundles.

The sample comes from the 55 most recently merged PRs returned by `gh pr list`.
It covers screen UI, a shared rendering library, Flyover, persistence, a broad compatibility feature, and tooling.
Recent history contains many test optimizations, so the sample includes two focused app fixes.
This is a varied sample, not a random estimate of all PRs.

Each local command compares the PR's landed commit with its first parent:

```bash
./test --dry-run --json --base MERGE_COMMIT^ --head MERGE_COMMIT
```

The complete diff includes both sides of renames. No path was removed to improve the result.
`--head` excludes local changes and uses the current checkout's graph.
This predicts local selection today; it does not execute or validate historical app revisions.
[selections.json](selections.json) records full commit identities and every selected/skipped bundle.

## Results

| PR | Changed paths | Ordinary selected / 22 | Image selected / 6 | Total skipped / 28 | Decision |
| --- | ---: | ---: | ---: | ---: | --- |
| [#506 — Shared screen roots](https://github.com/kyleve/Stuff/pull/506) | 149 | 4 | 1 | **23** | Affected bundles |
| [#496 — Device Layout Lab](https://github.com/kyleve/Stuff/pull/496) | 30 | 7 | 6 | **15** | Affected bundles |
| [#494 — Flyover pan/zoom](https://github.com/kyleve/Stuff/pull/494) | 9 | 4 | 2 | **22** | Affected bundles |
| [#537 — Remote-history counter](https://github.com/kyleve/Stuff/pull/537) | 2 | 4 | 1 | **23** | Affected bundles |
| [#495 — Data compatibility](https://github.com/kyleve/Stuff/pull/495) | 200 | 22 | 6 | **0** | Full fallback |
| [#503 — Astro prototype command](https://github.com/kyleve/Stuff/pull/503) | 11 | 22 | 6 | **0** | Full fallback |

The selected bundles explain the reductions:

- **#506:** `SnapshotKitTestingTests`, `WhereIntentsTests`, `WhereTests`, `WhereUITests`, and `WhereUISnapshotTests`. The other five image bundles are skipped.
- **#496:** `FlyoverTests`, `InstallerKitUITests`, `SnapshotKitTestingTests`, `SnapshotKitTests`, `WhereIntentsTests`, `WhereTests`, and `WhereUITests`, plus all six image bundles. Shared SnapshotKit changes reach every image consumer.
- **#494:** `FlyoverTests`, `WhereIntentsTests`, `WhereTests`, `WhereUITests`, `FlyoverSnapshotTests`, and `WhereUISnapshotTests`.
- **#537:** `WhereCoreTests`, `WhereIntentsTests`, `WhereTests`, `WhereUITests`, and `WhereUISnapshotTests`.
- **#495:** Full fallback begins at `.bumper/Sources/WhereProjectRules.swift`. The diff also contains specification inputs. These files are not safely mapped to particular iOS consumers.
- **#503:** Full fallback begins at `Tools/Tests/test_prototype.py`. Unknown tooling remains conservative.

Architecture, Flyover command, attribution, and backup-upgrader checks remain enabled in every case.
The full fallbacks also run host macro tests and use the grouped full-test scheme.
The four narrowed cases do not select host macro tests.

## Corrections verified against main

The original selector and new selector were given the same real paths and manifests.
These counts describe iOS bundles, not individual test cases.

| Changed input | Original selection | New selection |
| --- | ---: | --- |
| `Where/WhereUI/Tests/Support/TestStore.swift` | 1 | `WhereUITests` and `WhereUISnapshotTests` |
| `Where/WhereUI/Tests/Support/SnapshotWorldFixture.swift` | 1 | `WhereUITests` and `WhereUISnapshotTests` |
| `Shared/StuffTestHost/Sources/AppDelegate.swift` | 0 | All 26 consumers of that host |
| `Tools/InstallerKit/Site/src/components/EmptyState.astro` | 0 | `ToolsSnapshotTests` |
| `Tools/InstallerKit/stamp-installer-info.sh` | 0 | Full fallback: 28 |
| `Tools/test_runner.py` | 0 | Full fallback: 28 |
| `.circleci/continue.yml` | 0 | Full fallback: 28 |

Regression checks also cover missing Git history, complete merge-base diffs, renames, deletions, untracked files, spaces, Unicode, and newlines in paths.
Computed or unsupported manifest expressions stop with an error instead of returning a partial graph.

## Execution evidence and limits

All 58 selection, grouped-suite, and public-command contract tests passed.
The public-command regression verifies that normal execution uses the same filters shown by the preview.
Independent review reproduced the six saved selections and found no remaining actionable defects after the documented fixes.
Lint, shellcheck, and whitespace checks passed.

A real `./test CreditKitTests --no-generate` smoke run passed **11 tests** on iPhone 17 / iOS 27.2 after project generation.
It also passed the normal architecture and host checks.
The build took 50.230 seconds and the test phase took 12.908 seconds.
This validates the changed runner; it is not a timing comparison for any sampled PR.

The experiment measures bundle selection. It does not establish test-case savings, elapsed-time savings, or CI cost savings.
Bundles differ in size, and builds still compile the selected schemes.
The selected historical scopes were previewed, not all executed.
No image references or application code changed. CI remains full validation.

## Decision

Use the new local preview and selector to gather runtime evidence.
The sample shows substantial execution-scope reductions for focused feature changes, with visible conservative fallbacks for broad changes.
Keep CI full until a separate decision addresses runtime benefit, full-suite baselines, and the distinction between full and selected validation in CI reuse evidence.
