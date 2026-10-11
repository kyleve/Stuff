---
name: rebalance-snapshot-shards
description: Rebalance snapshot test shards from recent successful CircleCI timings. Use for periodic shard maintenance or an explicit snapshot rebalance.
---

Use the repository's `./snapshot-shards` command to maintain
[the shard plan](../../../.circleci/snapshot-shards.json).
Read the root [AGENTS.md](../../../AGENTS.md) and
[github-workflow](../github-workflow/SKILL.md) before changes.
The [README](../../../README.md) describes the commands and intake worker.

## Select timing samples

1. Fetch `origin/main`.
   Inspect the working tree.
   Start from current `main` in an isolated branch or a suitable clean worktree.
   Search open PRs for an existing rebalance before creating another PR.
   If a matching PR exists, update that branch through the GitHub workflow.
2. Run `./snapshot-shards check` to identify the current suite inventory and intake count.
   Read `.circleci/config.yml` for the current snapshot job and worker count.
3. Select the latest three successful snapshot jobs from distinct commits on `main`.
   Use `gh api` to read commit statuses and obtain the CircleCI job UUIDs.
   Retain each source commit, job URL, and completion date for the PR.
   Exclude runs with incompatible toolchains, runner classes, or snapshot selections.
   Prefer samples after changes to snapshot infrastructure or suite contents.
   If fewer comparable jobs exist, use the available complete jobs and report the sample count.
4. Download each job with `./circleci-artifacts JOB_UUID`.
   Select only `snapshot-timings/results-*.xml` beneath each job directory.
   Downloads can contain separate `exec-NNNN` directories for workers.
   Exclude unrelated XML, duplicate downloads, failed jobs, and partial results.
5. Verify that every selected job covers the current suite inventory exactly once across its workers.
   Reject JUnit documents with failures, errors, skipped tests, or invalid durations.
   An empty intake worker has no timing document.
   If coverage is incomplete, select another comparable successful job.
   If no complete sample exists, report the missing evidence and leave the plan unchanged.

Use the installed CLI help for exact flags.
These read-only commands locate the samples:

```bash
gh api 'repos/{owner}/{repo}/commits?sha=main&per_page=30'
gh api 'repos/{owner}/{repo}/commits/{sha}/status'
circleci job get JOB_UUID --json
circleci artifact JOB_UUID --json
./circleci-artifacts JOB_UUID
```

## Compare and apply

1. Run `./snapshot-shards balance` with one `--junit PATH` argument per selected timing document or timing-only directory.
   Unless the user requests a count change, keep the current planned shard count.
   Save stdout as an untracked JSON report; diagnostics go to stderr.
   The command uses median suite durations and leaves the plan unchanged without `--write`.
2. Preserve existing assignments. The command places intake suites, longest first, on the lightest planned shard.
   It then chooses the single-suite move that most reduces the maximum load, with stable suite/worker tie-breaks.
   It stops as soon as the estimated slowest worker improves by at least 5% against the original assignment, including intake.
   It never empties a planned shard or moves an existing suite more than once.
   If the target cannot be reached through these strictly improving moves, it discards them and retains only intake placements.
   This bounded local search does not guarantee the globally smallest move count; swaps and moves that temporarily worsen the maximum are not searched.
   Do not replace it with a fresh full rebalance merely to shave off additional seconds.
   An explicit shard-count change uses a full longest-processing-time assignment.
3. Read `changed`, `reason`, `beforeSeconds`, `afterSeconds`, `improvementPercent`, `movedSuites`, and `intakeSuites` from the report.
   Both assignments use the report's measured suite weights.
   Report per-worker totals, sample counts, existing-suite moves, and intake placements in the PR.
   `fullRebalanceSeconds` is a comparison estimate, not an instruction to apply that assignment or a proof of optimality.
   Label all totals as estimates of test duration, excluding CI startup and checkout time.
4. Apply a candidate only when `changed` is true, with the same command and `--write`.
   Intake always qualifies; otherwise moving existing suites requires at least 5% improvement.
   `--write` leaves the file byte-for-byte unchanged when no candidate qualifies.
   The written plan contains only the format version and assignments; keep timing measurements and sample metadata in the report and PR.
   Do not open a PR solely to refresh timing metadata.
   Keep `parallelism` equal to the planned shard count plus one intake worker and keep execution within each worker serial.
5. When revising an unmerged rebalance PR, compare against the latest main assignment, not the PR's earlier candidate.
   Save `git show origin/main:.circleci/snapshot-shards.json` to an untracked temporary plan and use `--plan PATH` before `balance`.
   After validating the report, apply to that temporary plan and copy the accepted plan into the checkout.
   If no candidate qualifies, restore main's plan instead of retaining the PR's superseded candidate.
   If the original PR has merged, use a follow-up branch from main and preserve the now-merged assignments.

## Verify and publish

Run these checks after a plan change:

```bash
./snapshot-shards check
python3 -m unittest discover -s Tools/Tests -p 'test_snapshot_shards.py'
git diff --check
```

Verify each `./snapshot-shards list NUMBER --total TOTAL` assignment against the current inventory.
Verify that assignments are disjoint and their union contains every suite.
After the rebalance, verify that intake is empty.
If tooling or CI configuration also changes, select further checks through [running-tests](../running-tests/SKILL.md).
A plan-only change does not alter rendering or require new snapshot references.

Commit and push the verified change through the GitHub workflow.
Open or update a ready-for-review PR with source job links, sample dates, before/after estimates, and verification results.
Report unavailable checks explicitly.
Unless the user requests a merge, leave the PR open for review.
