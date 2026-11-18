# 11 — Measure the combined local suite improvement

- Status: complete
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
Both runs are complete and their evidence is reconciled below. No new CI dispatch or Linear mutation is selected.

## Combined result

On Xcode 27.2 build 27B52 and iOS Simulator 27.2, the full local test phase improves from **860.623s to 805.560s**, saving **55.063s / 6.40%**.
This directly compares the source before both accepted changes with their combined implementation.
It replaces arithmetic across the separate historical pairs as the measured combined result; it does not establish each change's independent contribution in this run.

| Metric | Control `c6ad51144` | Candidate `05bb537a1` | Change |
| --- | ---: | ---: | ---: |
| Test phase | 860.623s | 805.560s | 55.063s saved (6.40%) |
| Exact test-function bodies | 833.665272s | 778.320154s | 55.345118s saved (6.64%) |
| Recorded capture work | 769.619s | 755.873s | 13.746s saved (1.79%) |
| All traced settling | 462.021455s | 442.487635s | 19.533821s saved (4.23%) |
| Render work within settling | 334.980766s | 321.376154s | 13.604612s saved (4.06%) |
| Sleep within settling | 114.979365s | 109.043257s | 5.936108s saved (5.16%) |
| Settling samples | 6,126 | 5,791 | 335 fewer |
| Sampled peak test-host RSS | 5,413.734MiB | 5,274.328MiB | 139.406MiB lower in this pair |

Reference-comparison work is 101.137s before and 103.120s after. The larger elapsed saving than capture-work saving is consistent with moving comparison alongside the following capture.
Operation totals can overlap and must not be added to reconstruct elapsed time. RSS is sampled approximately every 500ms and does not establish a memory improvement from one pair.

## Validation and retained evidence

- Both exact revisions pass `./test --snapshots --no-generate --record never --review --timings`, with a separate status-file destination. Each was regenerated through `./ide --no-open` and rebuilt. Build times of 17.362s and 21.271s are excluded, as are generation and other pre-test setup.
- Both runs pass 935 captures and 78 test functions, with zero retries. Test identities, capture identities, 4,797,647,739 pixels, 1,014 tiles, sizing, and final-settling policies match.
- The strict trace collector passes `--require-complete` for both runs. Calls decrease from 1,828 to 1,818: 62 measurement calls become immediate and ten Onboarding post-action calls disappear. All other reason/mechanism/floor/ceiling/quiet-duration/outcome policies match.
- The original reference assertions pass without recording or changing any reference. No separate PNG export or byte-identity claim is added for this measurement.
- Both use simulator `FF7C6753-1A36-4B9B-BD06-319B30EF0F2B`. Process sampling observes no competing test host. Each run launches fresh test-host processes; fixture process caches are not shared between runs.
- The runner restores `perf/snapshot-followup-experiments` at plan checkpoint `4931df97e` after each exact-revision run. Its runtime/build inputs still match candidate `05bb537a1`; only plan documentation differs. The unrelated local skill is restored with identical hashes after generation.

Raw scratch results are in `/private/tmp/stuff-snapshot-combined/{control,candidate}/`, with command logs alongside. A verified 41-file durable collection is at `/Users/kve/.codex/visualizations/2026/11/17/01a1e71b-13f1-7c80-8aee-e46d45c92d5b/snapshot-followup-results/combined-local/`.
It contains raw logs, exact extracted test-result JSON, source hashes/delta, trace records, policy checks, memory samples, commands, toolchain metadata, analysis helpers, and a SHA-256 manifest. Original `.xcresult` bundles remain in scratch; extracted JSON is retained in the durable collection.

This is one serial local pair with review/timing diagnostics enabled. It has no confidence interval and establishes no CI speedup. The earlier focused repetitions and per-PR full-suite measurements remain recorded in plans 04 and 07.

## Completion review and delivery

The documentation review recomputed the elapsed and exact-body differences, checked the raw test identities and strict trace reconciliation, and confirmed the unchanged runtime/build inputs and restored branch. No blocker remains.
Only the overview and this measurement record change. Swift formatting and additional implementation tests are unnecessary for these documentation edits; `git diff --check` passes. The executed full-suite pair supplies the requested measurement evidence.
This record is delivered in [PR #529](https://github.com/kyleve/Stuff/pull/529). The source changes responsible for the measured benefit remain in PRs #525 and #528; this record adds no optimization.
