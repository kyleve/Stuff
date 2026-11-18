# 11 — Measure the combined local suite improvement

- Status: executing
- Depends on: [04](04-validated-improvements.md) and [07](07-overlap-snapshot-work.md), both complete.
- Shared context: [Overview](README.md), US-01, R-02, R-04, R-07, and all existing exclusions.
- Issue: [STU-121](https://linear.app/kve/issue/STU-121). Its pending external update remains subject to the existing destination approval.

## Question and method

Measure both retained improvements together, instead of adding results from separate earlier pairs.
The earlier full local suite measurements already cover 935 captures and 78 test functions: PR #525 saves 16.809s (1.93%), and PR #528 saves 41.859s (4.91%).
The roughly 35% result for #525 applies only to its five affected families.

Run one fresh serial control/candidate pair on the same Mac and checkout-owned iPhone 17 simulator, with Xcode and iOS 27.2.
Use the exact committed control `c6ad511443cc605020ee319f165a87ed683f42d9` from PR #524 and candidate `05bb537a15a8880b415e6127b5eaafb95a2273f2` from PR #529.
The control includes the trace transport repair. The candidate's Swift source matches accepted PR #528; rejected prototypes are absent.
Build both revisions and use `./test --snapshots --no-generate --record never --review --timings` after generation with `./ide --no-open`.
Generation and build time are excluded from the primary test-phase measurement. Report exact test-body totals separately.

## Bounds and acceptance

- Use committed source without new experiment flags, image exports, reference recording, policy changes, or matrix changes.
- Run only one simulator workload at a time. Record revisions, commands, source hashes, toolchain, raw logs, result data, and sampled host RSS.
- Reconcile all 935 capture identities, pixels, tiles, test functions, and final policies. Permit only #525's intended 62 measurement-policy changes and ten removed post-action calls.
- Require passing reference assertions and zero retries for a clean timing comparison. Retain failures; do not present a retry-contaminated run as equivalent evidence.
- The effort is one pair. A failed or interrupted member permits one replacement attempt only after its cause is understood. Persistent environment failures produce an inconclusive result.
- This is a single local pair, not a confidence interval, per-PR attribution, or a CI speedup claim. Report adverse or inconclusive results honestly.
- Restore the original branch and generated project after the control. Preserve unrelated local files. Publish only the plan and evidence summary in PR #529; no runtime source is changed.

## Execution steps

1. Commit this measurement plan, record the original branch, and inspect the clean source and available simulator.
2. Temporarily check out the exact control, regenerate, and run the full suite. Save the measured run and return to the original branch even on failure.
3. Regenerate the accepted candidate and run the identical suite command. Verify candidate source matches `05bb537a1` outside plan documentation.
4. Parse both logs through the strict trace collector and both result bundles for exact test durations. Compare coverage, policies, retries, test phase, capture work, settling, comparison, and RSS.
5. Retain hashed artifacts, record the result and limitations here, review the documentation diff, and update PR #529 through the existing stack.

## Review and resume point

Plan reviewed on 2026-11-18 against `05bb537a1`, the two completed implementation records, the root test command, and current stack state. The chosen control and candidate share the trace repair and test matrix. Existing implementation validation remains intact; this adds a measurement and no architecture, so no new Mermaid or Swift sketch applies.
No blocking question remains. Begin with the control run; no new CI dispatch or Linear mutation is selected.
