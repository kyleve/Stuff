---
name: rebalance-snapshot-shards
description: Rebalance snapshot test shards from successful CircleCI timing samples.
---

# Rebalance snapshot shards

Use `./snapshot-shards`; its `--help` owns flags and [its implementation](../../../Tools/snapshot_shards.py) owns the balancing algorithm.
[github-workflow](../github-workflow/SKILL.md) owns publication.

## Select timing samples

- Start from current `origin/main` in a clean branch/worktree, or continue an unfinished matching rebalance PR.
- Run `./snapshot-shards check` and read `.circleci/continue.yml` for current inventory and worker count.
- Select the latest three successful snapshot jobs from distinct main commits with compatible toolchains, runner classes, and selections. Prefer runs after relevant infrastructure/suite changes. Report fewer samples when fewer comparable jobs exist.
- Obtain CircleCI job UUIDs from `gh api` commit statuses. Download with `./circleci-artifacts JOB_UUID`.
- Use only `snapshot-timings/results-*.xml`, including worker `exec-NNNN` directories. Each job must cover the current inventory exactly once, without failures, skipped tests, or invalid durations. Empty intake has no timing file.
- If no complete comparable sample exists, report missing evidence and leave the plan unchanged.

## Apply a candidate

Run `./snapshot-shards balance` with a `--junit PATH` per timing file or timing-only directory.
Keep the shard count unless the user requests a change.
Inspect the JSON report before repeating the same command with `--write`.

Apply only a qualifying candidate (`changed: true`): intake qualifies; moving existing suites requires at least 5% estimated improvement.
Use the command's candidate, not a hand-written full rebalance. `fullRebalanceSeconds` is comparison data, not proof of optimality.
Keep timing data in the report/PR, not the execution plan.
Keep CI parallelism equal to planned shards plus one intake worker, with serial execution within each worker.

When revising an open PR, balance against the latest main assignment using a temporary `--plan PATH`.
Copy the qualifying result into the checkout; if none qualifies, restore main's plan.
After a prior PR has merged, use a new branch based on its merged assignments.

## Verify and publish

Run `./snapshot-shards check` and `git diff --check`.
Confirm the written plan covers the current inventory and leaves intake empty.
Tooling or CI changes need additional checks through [running-tests](../running-tests/SKILL.md).

Report source commits/job links, completion dates, sample counts, estimated before/after worker totals, existing-suite moves, intake placements, and checks.
Estimates exclude CI startup and checkout.
Do not publish a PR solely to refresh timing metadata; leave a changed plan's PR open for review.
