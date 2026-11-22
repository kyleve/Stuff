# 01. Run compiled inventory validation on the unit worker

Status: executing. Main at `327b3f58e` has the required shared artifacts, worker simulator, and unfiltered comparison. This trial covers R-01 through R-03 under X-01 in the [overview](README.md).

## Baseline

| Builder | Inventory step | Simulator setup | Xcode discovery |
| --- | ---: | ---: | ---: |
| [#5008](https://app.circleci.com/workflow/53d5f3f4-4dae-4334-908c-0b14cbeaf808) | 113.505 s | 37.888 s | 59.515 s |
| [#5014](https://app.circleci.com/workflow/81111211-41a1-41ec-bd91-0305e8b0f8d0) | 100.614 s | 37.560 s | 58.852 s |
| [#5036](https://app.circleci.com/workflow/19ab3f24-001b-465c-8483-8e6ab67568a4) | 103.897 s | 37.048 s | 61.522 s |
| [#5041](https://app.circleci.com/workflow/2ac4fe06-ecb5-44bf-af06-7407d08595b3) | 108.457 s | 37.924 s | 56.705 s |

Every run found 73 suites. The step averaged 106.618 seconds, about 711 credits at 400 per minute. The unit job finished 26–91 seconds before snapshots. In the [100-PR replay](https://github.com/kyleve/Stuff/pull/556), the old trigger matched 24 of 89 paid final revisions and 23 of 68 paid earlier revisions.

## Execution

1. Move the existing unfiltered enumeration and comparison into the required unit job, after JUnit export. The builder can then hand off the products immediately. Keep the current project/source triggers, and include the gate script's own path so a change to it exercises the real integration.
2. Exercise unrelated, project, snapshot and gate-only changes as well as enumeration and comparison failures. Check the production CircleCI configuration, the real source inventory, shell lint and the workflow helpers. Use the CI job's existing failure diagnostics.
3. Compare a full affected PR head against the four builders above. Require all 73 suites and the baseline unit and snapshot identities and outcomes. Price each inventory step on its own executor, and record full-job credits and wall time separately. Retain the move if it preserves coverage and reduces compute. If worker execution fails, diagnose the attached manifest, simulator selection, enumeration log and comparison before deciding whether to retain the change.

The linked implementation PR will hold the ordinary CI job receipts on the final revision.
