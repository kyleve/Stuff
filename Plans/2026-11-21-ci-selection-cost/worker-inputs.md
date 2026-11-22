# Worker inputs for the native CI replay

## Measured full runs

The three full workflows used the same logical bundles and shard assignments. CircleCI Insights supplies total and job credits, plus elapsed workflow and builder times. #555 is the ordinary full build. Both #554 builders also ran the conditional snapshot inventory check. Each model keeps its own observed builder costs throughout the replay. [Shard plan](https://github.com/kyleve/Stuff/blob/327b3f58e/.circleci/snapshot-shards.json) · [Worker definitions](https://github.com/kyleve/Stuff/blob/327b3f58e/.circleci/continue.yml#L408-L554)

| Workflow | PR revision | Native credits | Builder credits | Unit credits | Snapshot credits | Native gate s | Builder s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [#555](https://app.circleci.com/workflow/4d564cf3-6055-4f7d-8335-8ec870e3c961) | [506d87bf1](https://github.com/kyleve/Stuff/commit/506d87bf1a5f1a4e410d53dc6f78cd7da4186851) | 7069 | 1377 | 1540 | 4152 | 771 | 245 |
| [#554 first](https://app.circleci.com/workflow/53d5f3f4-4dae-4334-908c-0b14cbeaf808) | [6190b4f16](https://github.com/kyleve/Stuff/commit/6190b4f1652cce275dc8ba5f945e9f131098e1cd) | 7827 | 2168 | 1329 | 4330 | 904 | 365 |
| [#554 final](https://app.circleci.com/workflow/81111211-41a1-41ec-bd91-0305e8b0f8d0) | [b49bdf1b1](https://github.com/kyleve/Stuff/commit/b49bdf1b10a33d5c0c60f27e6a321840d8952932) | 7656 | 2064 | 1363 | 4229 | 842 | 352 |

## Worker timing

“VM span” runs from the first step start to the last step finish, including gaps. “Finish” is measured from the builder job's completion and includes each VM's observed start delay. “Case time” sums JUnit durations assigned to that worker. The residual includes setup, simulator boot, host launches, reporting and artifact transfer where present. The intake worker checked out the repository and exited after finding its assignment empty in all three runs.

| Run | Worker | VM span s | Finish s | Case time s | Residual s |
| --- | --- | --- | --- | --- | --- |
| #555 | Unit | 473.806 | 478.677 | 289.095 | 184.711 |
| #555 | Snapshot 0 | 458.187 | 524.904 | 328.035 | 130.152 |
| #555 | Snapshot 1 | 390.429 | 453.245 | 282.401 | 108.028 |
| #555 | Snapshot 2 | 394.550 | 451.555 | 282.991 | 111.559 |
| #555 | Intake | 6.837 | 21.121 | 0.000 | 6.837 |
| #554 first | Unit | 399.918 | 447.393 | 263.762 | 136.156 |
| #554 first | Snapshot 0 | 474.846 | 538.124 | 336.322 | 138.524 |
| #554 first | Snapshot 1 | 439.375 | 500.210 | 327.701 | 111.674 |
| #554 first | Snapshot 2 | 381.639 | 441.476 | 267.683 | 113.956 |
| #554 first | Intake | 7.708 | 61.813 | 0.000 | 7.708 |
| #554 final | Unit | 410.266 | 462.979 | 266.550 | 143.716 |
| #554 final | Snapshot 0 | 425.424 | 489.194 | 298.213 | 127.211 |
| #554 final | Snapshot 1 | 416.823 | 477.068 | 293.629 | 123.194 |
| #554 final | Snapshot 2 | 422.107 | 482.069 | 279.791 | 142.316 |
| #554 final | Intake | 8.249 | 65.007 | 0.000 | 8.249 |

## Bundle weights

The JUnit export for each run contains 3,009 ordinary results and 80 snapshot results. For each result, the original module comes from the prefix of its JUnit `file` path. Each image result also maps to one of the 73 suites in the shard plan. Each cell below sums case seconds for one bundle on one worker. `BroadwayCatalogTests` launches a host with zero reported cases and still counts as an assignment. [Job test metadata](https://circleci.com/docs/api/v2/#operation/getTests)

| Worker | Logical bundle | #555 s | #554 first s | #554 final s |
| --- | --- | --- | --- | --- |
| Unit | `BroadwayCatalogTests` | 0.000 | 0.000 | 0.000 |
| Unit | `BroadwayCoreTests` | 0.029 | 0.025 | 0.030 |
| Unit | `BroadwayUITests` | 0.310 | 0.293 | 0.306 |
| Unit | `CreditKitTests` | 0.018 | 0.017 | 0.015 |
| Unit | `FlyoverTests` | 2.905 | 2.879 | 3.210 |
| Unit | `InspectorTests` | 0.590 | 0.553 | 0.604 |
| Unit | `InstallerKitTests` | 0.155 | 0.111 | 0.146 |
| Unit | `InstallerKitUITests` | 1.518 | 1.005 | 1.210 |
| Unit | `JournalKitTests` | 0.071 | 0.059 | 0.082 |
| Unit | `LifecycleKitTests` | 0.365 | 0.168 | 0.193 |
| Unit | `LifecycleKitUITests` | 3.917 | 4.242 | 3.796 |
| Unit | `PeriscopeCoreTests` | 1.925 | 1.661 | 1.930 |
| Unit | `PeriscopeToolsTests` | 2.577 | 2.317 | 2.426 |
| Unit | `PeriscopeUITests` | 0.051 | 0.032 | 0.027 |
| Unit | `RegionKitTests` | 0.251 | 0.226 | 0.254 |
| Unit | `SnapshotKitTestingTests` | 93.159 | 85.111 | 83.027 |
| Unit | `SnapshotKitTests` | 0.025 | 0.021 | 0.023 |
| Unit | `WhereCoreTests` | 43.134 | 41.829 | 38.459 |
| Unit | `WhereCrashReportingTests` | 0.000 | 0.000 | 0.001 |
| Unit | `WhereIntentsTests` | 0.276 | 0.264 | 0.304 |
| Unit | `WhereTests` | 0.734 | 0.482 | 0.454 |
| Unit | `WhereUITests` | 137.085 | 122.467 | 130.053 |
| Snapshot 0 | `FlyoverSnapshotTests` | 13.990 | 13.486 | 15.011 |
| Snapshot 0 | `InspectorSnapshotTests` | 2.887 | 2.918 | 2.935 |
| Snapshot 0 | `InstallerKitUISnapshotTests` | 6.236 | 5.318 | 5.094 |
| Snapshot 0 | `PeriscopeToolsSnapshotTests` | 2.950 | 2.811 | 3.573 |
| Snapshot 0 | `ToolsSnapshotTests` | 99.655 | 102.751 | 95.310 |
| Snapshot 0 | `WhereUISnapshotTests` | 202.317 | 209.038 | 176.290 |
| Snapshot 1 | `InstallerKitUISnapshotTests` | 8.331 | 8.711 | 7.399 |
| Snapshot 1 | `WhereUISnapshotTests` | 274.070 | 318.990 | 286.230 |
| Snapshot 2 | `InstallerKitUISnapshotTests` | 24.971 | 25.556 | 26.046 |
| Snapshot 2 | `WhereUISnapshotTests` | 258.020 | 242.127 | 253.745 |

## Reproduce a projection

1. Take the PR's selected bundles from the [replay](replay.md) and use one full run's columns throughout. A full fallback or existing documentation skip saves zero. Assume one validation per landed diff, the current bundle graph, the existing physical shard plan and the same compiled products.
2. On a worker with any selected bundle, sum the omitted bundles' case seconds. Subtract that sum from the measured finish. Multiply the sum by `200 / 60` for avoided credits on a medium Mac. This keeps every second of non-case work, including host startup and artifact attachment, on every active worker. [Machine rates](../../CI_COST.md#machines-and-rates)
3. If selection empties a previously active worker, replace its VM span with the measured intake span. Preserve that worker's start delay. For credits, the full unit allocation equals its Insights job charge. Allocate the snapshot job's reported charge among all four snapshot VMs in proportion to their VM spans. Subtract the intake allocation from the emptied worker's full allocation. The intake itself always contributes zero savings. This retains a short Mac allocation for each empty worker.
4. Sum the four active workers' credit differences. For turnaround, compare the largest original and projected finishes across all five workers. Repeat with only the snapshot workers for the snapshot gate. The builder and time before fan-out stay fixed. This measures the native gate only. GitHub checks can finish later.
5. Aggregate the per-PR differences before rounding. The denominator for average savings per full validation is 89. The 11 existing lightweight PRs contribute zero incremental savings. For a percentage of native cost, use 89 times the calibration's observed total. A selected result would need a separate full-validation policy to qualify for merge reuse. [Existing validation evidence](https://github.com/kyleve/Stuff/blob/327b3f58e/Tools/ci_merge_validation.py)

Worker timing, JUnit and provider billing are separate measurements. The calculation uses step timestamps for elapsed changes and reported job totals for the cost of an emptied worker. The active-worker price uses the documented per-second rate. Queue delays, fixed work and case times can change on future runs. The three calibrations expose that variability.
