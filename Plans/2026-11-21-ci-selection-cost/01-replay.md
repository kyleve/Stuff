# 01. Replay and price 100 merged PRs

Status: executing. Depends on the [landed selector](../2026-11-21-affected-test-selection/01-selection.md). The report delivers R-01 through R-03 under X-01.

1. Pin the 100 latest PRs merged into main through #555. For each landed commit run `./test --dry-run --json --base <first-parent> --head <merge>` on one checkout of the merged selector. Apply the real documentation-only policy and retain full fallbacks, both sides of renames, and PR identities.
2. Map each selected logical bundle to JUnit case seconds and its actual CircleCI worker. Keep the builder, handoff, and fixed time for active workers. Model an early exit only when the worker has no assignments. Compare with multiple successful full runs and report the slowest parallel worker before and after each selection.
3. Count how often full-PR evidence would still be needed to reuse validation at merge. Compare modeled gross credit savings with the cost of validating the final tree and the historical frequency of unchanged installer-site fixture inputs. Retain observed data, model assumptions, and a recommendation separately.

Acceptance requires complete input coverage, reproducible worker-level arithmetic, zero incremental savings on already-skipped or fully selected diffs, and separate credit and elapsed-time results. A finding that selection would cost more meets acceptance. Temporary analytics stay outside the shipping tools. Review the evidence and preserve full CI throughout the experiment.
