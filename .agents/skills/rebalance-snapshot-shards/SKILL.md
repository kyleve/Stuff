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
   The command uses median suite durations and leaves the plan unchanged without `--write`.
2. Compare both assignments with the candidate's measured suite weights.
   Include the existing intake shard in the current assignment.
   Report the current and proposed maximum loads, per-shard totals, sample counts, and intake suites.
   Label these numbers as estimates of test duration, excluding CI startup and checkout time.
3. If intake contains suites, apply the candidate.
   If intake is empty and the maximum load estimate decreases by at least 5%, apply the candidate.
   Otherwise, leave tracked files unchanged and report that no rebalance is needed.
   Do not open a PR solely to refresh timing metadata.
4. Apply an accepted candidate with the same command and `--write`.
   Keep `parallelism` equal to the planned shard count plus one intake worker.
   Keep test execution within each worker serial.

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
