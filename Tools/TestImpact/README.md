# Snapshot selection experiment

The experiment measures test execution savings within existing targets. WhereUI remains one target.
Normal CI runs every test. Only the separate **Test Selection Experiment** workflow can select fewer tests.

## Components

`./test --impact` owns the command interface. Python modules under `Tools` own selection policy, metadata, accounting, and reports.
This Swift package supplies `test-impact-index`. It reads a JSON request from stdin and writes file evidence to stdout.
The request names the checkout, source files, compiler index, temporary database, and Xcode's `libIndexStore.dylib`.
The response includes source ownership, compiler symbol identities, dependencies, capture roots, freshness, and syntax limitations.

[XcodeSelectiveTesting 0.15.1](https://github.com/mikeger/XcodeSelectiveTesting) supplies the target graph.
The adapter validates its local edges against Tuist and SwiftPM declarations. It preserves upstream diagnostics.
The upstream tool reports incorrect resource paths for this repository's custom package layout.
The adapter adds tracked package resources and installer generator inputs explicitly. Unknown inputs select everything.
It does not use upstream turbo mode or change Xcode test plans.

SwiftSyntax identifies capture roots and source limitations. IndexStoreDB supplies resolved file references.
The collector joins members to their repository-owned types. It does not join every implementation through a shared protocol.
Debug guards and previews are known inputs under the pinned Debug configuration. Other conditional compilation triggers a fallback.
Unrecognized snapshot capture roots always run when their bundle is affected.

## Local commands

Prepare the tools and build with an index:

```sh
./test --impact bootstrap
TEST_IMPACT_INDEX_STORE="$PWD/.build/test-impact/build-index" \
  ./test --everything --build-artifacts "$PWD/.build/test-impact/build"
./test --impact collect \
  --index-store .build/test-impact/build-index \
  --build-manifest .build/test-impact/build/manifest.json \
  --output .build/test-impact/head.json
```

Collect metadata from a committed tree. The diagnostic `--allow-dirty` option produces metadata that the planner rejects.
Generate the project through `./ide --no-open` before collection if its inputs changed.

Create a plan from matching base and head metadata:

```sh
./test --impact plan --base origin/main --head HEAD --mode snapshot \
  --metadata .build/test-impact/head.json \
  --base-metadata .build/test-impact/base.json \
  --output .build/test-impact/plan.json
```

The base metadata must match the merge base. Missing metadata selects whole bundles and records the reason.
The JSON output includes exact suites and reasons. An adjacent Markdown report explains the result.
The planner does not run tests or change ordinary `./test` scope.

## CI experiment

The `test_impact_mode` pipeline parameter defaults to `off`. Available experiment modes are `full`, `target`, `snapshot`, and `shadow`.
The `test_impact_base` parameter names the destination ref. Its default is `origin/main`.
Only `target` and `snapshot` filter execution. `shadow` collects both plans and runs the full suite.
`full` runs the existing configuration without analysis overhead.
Target mode does not build or collect the compiler index.

All modes build the complete iOS schemes and release audiences. Snapshot workers retain their existing assignments.
Each worker intersects its assignment with the plan before product transfer, LFS hydration, and simulator startup.
The existing execution guard verifies the selected snapshot assignment exactly.
Experiment checks have distinct names and cannot replace the normal required checks.

The builder caches revision-bound metadata and publishes it under `test-impact/history`.
Plans appear under `test-impact/plans`. A missing worker plan fails the experimental job rather than skipping tests.
The first indexed base run seeds history. A missing or incompatible base produces full selection.
The cache uses the collector source fingerprint, dependency lock, and pinned Xcode build.
Plan caches also include the workflow identity, so reruns cannot consume an earlier run's selection.
Policy changes also invalidate metadata. Each snapshot worker publishes an `impact-evidence-*.json` file beside its JUnit artifact.
The file binds checksums to the revision, toolchain, mode, and workflow. Keep each evidence file beside its downloaded XML.

## Evaluation procedure

1. Finish the existing worker and host-check comparison before freezing the baseline.
2. Initialize the budget ledger with that baseline revision.
3. Collect a full indexed base run in shadow mode.
4. Collect shadow plans for 14 days. Aim for 30 distinct PR revisions.
5. Compare plans with complete snapshot JUnit evidence through `./test --impact audit`.
6. Investigate every omitted failure. Record `regression`, `flake`, or `unresolved` by suite identifier.
7. Choose leaf UI, shared core, installer, documentation, and broad configuration revisions.
8. Run full, target, and snapshot modes twice per revision. Rotate the mode order and run sequentially.
9. Keep toolchains, worker classes, dependency caches, and shard assignments equivalent.
10. Pair each CircleCI run with matching GitHub checks. Include their completion in end-to-end time.

Run `./test --impact replay --metadata-directory DIR --output report.json` for the latest 100 first-parent changes.
Use revision-named metadata files. Missing historical metadata remains an explicit gap, not a savings estimate.
Do not use today's graph to claim historical savings.

Audit one full workflow against its previously generated plan:

```sh
./test --impact audit --plan plan.json --junit artifacts/results-*.xml \
  --evidence artifacts/impact-evidence-*.json --output audit.json
```

The audit rejects mixed workflows, different revisions, changed artifacts, and incomplete suite coverage.
Supply `--verdicts verdicts.json` after investigating failures. The file maps `Bundle/Suite` to a verdict.

## Budget and reports

```sh
./test --impact budget --ledger .build/test-impact/experiment.json init --baseline BASELINE_SHA
./test --impact budget --ledger .build/test-impact/experiment.json reserve \
  --key leaf-full-1 --revision HEAD --mode full --category leaf-ui --repetition 1
# Dispatch once, then record the pipeline/workflow identity beside this reservation.
./test --impact budget --ledger .build/test-impact/experiment.json finish \
  --key leaf-full-1 --result result.json
./test --impact budget --ledger .build/test-impact/experiment.json report
```

Reserve before dispatch. An unresolved reservation blocks another run, including after an uncertain network response.
The ledger reserves $75 for one complete workflow and permits at most 30 runs within the $250 budget.
Record actual credits after each terminal workflow. Failed and canceled runs consume budget but do not establish successful savings.
The large reservation can stop the experiment before all 30 runs. Do not reduce it to exhaust the budget.
Monitor active runtime and cancel an experiment if remaining budget becomes insufficient.
Count duplicate runs and shadow overhead. Keep the ledger outside Git, and retain it with the raw experiment artifacts.

Each result contains `revision`, `mode`, `status`, `elapsedSeconds`, `queueSeconds`, and `runtimeSeconds`.
Include `workflowURL`, `githubURL`, `criticalPath`, and phase durations as evidence.
Use `creditsUsed` from CircleCI Insights when available.
Otherwise provide every worker under `workers`, with `resourceClass` and `seconds`. Estimates use 400/200 credits per minute and $0.0006 per credit.
Queue seconds mean waiting on the critical path, not the sum of parallel worker queues.
Report storage charges and billing discounts separately. Public standard GitHub runners add no compute charge under the current policy.

The report compares successful runs at the same revision and repetition. It gives paired medians, ranges, and mean cost differences.
It compares each mode with full execution and snapshot selection with target selection.
Also report analysis overhead, fallbacks, failure verdicts, and the observed change mix.
The adoption thresholds are 20% compute savings for target selection and another 10% for snapshot selection.
A meaningful speed claim requires 10% lower median end-to-end time. Disclose queue variability and sample size.
Any confirmed missed regression or unresolved omitted failure blocks a rollout recommendation.

## Validation limits

File references are experimental evidence, not a complete behavioral call graph.
The compiled fixture proves transitive references, implicit member access, stale-index rejection, and detection of a deliberate helper regression.
It does not prove visual regression recall for WhereUI. Real mutation scenarios and full shadow results supply that evidence.
Green runs alone cannot establish a population detection rate.

Coverage instrumentation, build avoidance, result caching, and production skipping remain outside this experiment.

## Tests

The separate `Test Selection Tools` GitHub workflow runs these checks when the experiment files change.
It does not alter the existing required check names.

```sh
python3 -m unittest discover -s Tools/Tests -p 'test_test_impact*.py'
swift test --package-path Tools/TestImpact --force-resolved-versions
```
