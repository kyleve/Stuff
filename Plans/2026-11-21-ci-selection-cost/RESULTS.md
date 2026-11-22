# What affected-test selection would save

**Keep full validation on the mergeable PR head. Try the installer-site fixture cache first.** Replaying one landed diff per PR produces a gross selection opportunity of **35,272 native credits across 100 PRs**. Five extra full validations at the ordinary #555 rate would consume 35,345 credits. The cache can reduce work on a full run and preserve the evidence that lets main reuse it. [Full workflow on #555](https://app.circleci.com/workflow/4d564cf3-6055-4f7d-8335-8ec870e3c961)

## Most PRs keep all active workers

We ran the landed selector on the 100 most recently merged PRs into main through #555. They form a contiguous first-parent sequence, from #414 on October 22 through #555 on November 22, 2026 UTC. Today's documentation policy would already skip 11. Of the other **89**, 60 select everything and 29 narrow. In the 60 full fallbacks, the first reported reason names a global build or test input in 31 and an unowned input in 29. Fourteen renames across eight PRs contributed both old and new paths. All six selections from the original experiment reproduced exactly. [PR-by-PR results](replay.md) · [Earlier experiment](../2026-11-21-affected-test-selection/RESULTS.md)

| Across the 89 full validations | Projected result using #555 timing |
| --- | ---: |
| Gross credit saving per validation | 396 credits (5.61%) |
| PRs with a shorter native gate | 23 |
| Mean native gate reduction across all 89 | 24.7 s |
| Median native gate reduction across all 89 | 0 s |
| Mean native gate reduction on the 23 that benefit | 95.6 s |
| PRs that empty at least one active worker | 3 |
| PRs that empty all three active snapshot workers | 2 |

The two unit-fixture changes, #552 and #553, could exit all three snapshot workers early. The installer snapshot change, #431, could exit the unit worker and two snapshot workers. Those three examples account for about 40% of the modeled savings. The other 26 narrowed PRs all select WhereUI snapshots, which span the three active shards. Six narrowed PRs save worker credits yet leave the slowest worker's finish time unchanged. The empty intake worker receives zero incremental savings throughout. [Per-worker results](replay.md)

## Measured inputs and sensitivity

The primary full run on #555 used **7,069 credits**: 1,377 for the builder, 1,540 for unit tests, and 4,152 for snapshots. The builder skipped Xcode inventory enumeration. The two #554 workflows exercised the same graph and also paid for inventory enumeration on the builder. All three supply complete test reports with 3,009 unit and 80 snapshot results. [Primary run](https://app.circleci.com/workflow/4d564cf3-6055-4f7d-8335-8ec870e3c961) · [First #554 run](https://app.circleci.com/workflow/53d5f3f4-4dae-4334-908c-0b14cbeaf808) · [Second #554 run](https://app.circleci.com/workflow/81111211-41a1-41ec-bd91-0305e8b0f8d0)

| Full-run timing source | Gross credits saved in 100 PRs | Native credits saved across 89 full validations | Mean native gate reduction across 89 |
| --- | ---: | ---: | ---: |
| #555 | 35,272 | 5.61% | 24.7 s |
| #554, first | 34,800 | 5.00% | 18.3 s |
| #554, second | 33,877 | 4.97% | 10.6 s |

The model charges the full builder on each eligible PR. It preserves active workers' setup, handoff, process startup, reporting and queue offsets. It subtracts the JUnit case seconds owned by skipped bundles. An empty worker still pays for checkout and the early-exit check, priced using the current intake worker. Pricing only test-body changes and crediting zero extra for early exits gives **31,875 credits** on the primary run. CI branching, selector execution and a rerouted partial run could add overhead. Historical PRs used different code, shard layouts, machines and prices. This replay estimates what their diffs would select on one pinned tree. [Model and timing inputs](worker-inputs.md)

## Full results at merge

Main currently checks the PR head, Git tree, workflow, job names and statuses when reusing validation. A selected run needs its own coverage identity. Using today's full job contexts for partial coverage could cause main to accept missing tests. A subsequent full run on every narrowed final head would require 29 full runs if all 29 otherwise qualified for reuse. At 7,069 credits each that conditional scenario costs **169,729 more credits net** across the sample. The actual number of additional merge runs would depend on existing reuse eligibility. [Evidence contract](https://github.com/kyleve/Stuff/blob/327b3f58e/Tools/ci_native_evidence.py) · [Merge policy](https://github.com/kyleve/Stuff/blob/327b3f58e/Tools/ci_merge_validation.py)

We also replayed **71 successful earlier PR heads** using the base and head recorded by CircleCI. Twenty-four runs across seven PRs could save **25,803 credits** while leaving a full validation on the final tree. This figure benefits from hindsight. None of those seven PRs used draft status, so a draft-only rule would have captured zero of the projected saving. Canceled and failed runs fall outside this replay. [Earlier PR runs and pricing](earlier-runs.md)

## Compare the installer fixture cache

Of the 89 paid diffs, **58 leave a conservative fixture cache key unchanged** from the base and 31 change at least one input. The input screen covers the installer renderer, fixture generators, site source, dependency lockfile, tool and Xcode pins, project and native CI configuration, and both registered artwork paths on either side of each diff. The full path list and per-PR results are retained. [Historical inputs](replay.md)

The three builders spent 28.073, 28.720 and 29.250 seconds in `npm ci`. At 400 credits per minute, 58 successful warm hits would save **10,855–11,310 credits** in that step alone across the 100 landed examples, before cache lookup, restore, and miss overhead. The primary estimate is **11,105 credits**, or about 125 per paid validation. That calculation assumes a compatible cache entry from the base is available and covers the Mac's site dependencies. The generator's runtime is excluded. An unchanged input set establishes the opportunity for a hit. Actual hit rate, byte-identical output and net runner savings need a cache trial. [Installer fixture generator](https://github.com/kyleve/Stuff/blob/327b3f58e/Tools/Tests/Fixtures/installer_update_site_snapshots.py)

Across the same 100 final diffs and 71 earlier runs, selection on earlier heads alone offers 25,803 gross credits with hindsight. The fixture cache has 103 potential hits, worth 19,721 credits under the primary timing. One extra full gate costs more than the roughly 6,100-credit difference. The cache is the next experiment because it can benefit both early and final runs without changing when a PR becomes mergeable.

## A correctness gap found during the replay

Changing either registered Where app icon in isolation selects only `WhereTests`. The installer fixture reads those exact icon bytes and embeds them in the HTML that `ToolsSnapshotTests` captures. Two public CLI replays reproduced the missing suite. No landed diff in the sample changed either registered icon. This finding matters before enforcing selections in CI and is tracked separately. [STU-345](https://linear.app/kve/issue/STU-345/select-install-site-snapshots-when-registered-artwork-changes)
