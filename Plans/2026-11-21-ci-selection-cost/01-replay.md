# 01. Replay and price 100 merged PRs

Status: complete. Depends on the [landed selector](../2026-11-21-affected-test-selection/01-selection.md). The report delivers R-01 through R-03 under X-01.

1. Pin the 100 latest PRs merged into main through #555. For each landed commit run `./test --dry-run --json --base <first-parent> --head <merge>` on one checkout of the merged selector. Apply the real documentation-only policy and retain full fallbacks, both sides of renames, and PR identities.
2. Map each selected logical bundle to JUnit case seconds and its actual CircleCI worker. Keep the builder, handoff, and fixed time for active workers. Model an early exit only when the worker has no assignments. Compare with multiple successful full runs and report the slowest parallel worker before and after each selection.
3. Count how often full-PR evidence would still be needed to reuse validation at merge. Compare modeled gross credit savings with the cost of validating the final tree and the historical frequency of unchanged installer-site fixture inputs. Retain observed data, model assumptions, and a recommendation separately.

Acceptance requires complete input coverage, reproducible worker-level arithmetic, zero incremental savings on already-skipped or fully selected diffs, and separate credit and elapsed-time results. A finding that selection would cost more meets acceptance. Temporary analytics stay outside the shipping tools. Review the evidence and preserve full CI throughout the experiment.

## Evidence and disposition

Ran 100 landed diffs and the 71 successful nonfinal PR contexts identified in CircleCI's historical records. The [report](RESULTS.md) compares the alternatives. The [landed selections](replay.md), [earlier PR contexts](earlier-runs.md) and [measured worker inputs](worker-inputs.md) retain the reproduction data. An independent calculation matched all three full-run calibrations. Two isolated dry runs reproduced a missed installer artwork dependency, tracked in [STU-345](https://linear.app/kve/issue/STU-345).

The analysis branch is `perf/price-affected-test-selection`. The next decision is whether to time a fixture-cache hit and miss on the shared builder. [STU-344](https://linear.app/kve/issue/STU-344)
