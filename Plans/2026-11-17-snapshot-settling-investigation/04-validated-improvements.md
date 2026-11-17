# 04 — Deliver validated improvements

- Status: complete
- Depends on: [03](03-controlled-experiments.md), complete and published in [PR #525](https://github.com/kyleve/Stuff/pull/525) at `433450cba`.
- Shared context: [Overview](README.md), R-04 and X-02–X-04.

## Intended outcome

Remove proven redundant measurement settles and place artwork preparation before final settling. Preserve the complete image matrix, geometry, reference data, tolerances, cancellation, retry freshness, and all final capture floors.

## Selected changes

Settings was rejected: all 16 early measurements changed capture height. Its existing measurement settle remains necessary even with synchronous data.

Plan 03 accepts setting `measurementReadiness: .immediate` explicitly on five synchronous fixture providers:

- `Shared/InstallerKitUI/Sources/UpdateBuildView.swift` and `UpdateHistoryView.swift`: fresh cached catalogs and a fixed fixture clock keep automatic refresh cache-only.
- `Where/WhereUI/Sources/Resolution/FlightReviewPointRow.swift`: prepared point data and a fixed-height map capture surface.
- `Where/WhereUI/Sources/Settings/PrivacyPassportCard.swift`: supplied disclosure content; motion changes the surface, not layout.
- `Where/WhereUI/Sources/Onboarding/OnboardingThemeSelectionView.swift`: supplied selection and artwork that preserves card layout.

Move only Onboarding's existing artwork hook from `onReadyToSnapshot` to `prepareForCapture`. Keep mounted-card final settling: warming the path cache does not certify publication into each card model.
The first cold control/candidate pair passes ten pixel-identical captures, including visible California artwork in both specimens. Its capture total falls from 12.536s to 6.076s; both repeated 62-capture pairs and the delayed oracle are also pixel-identical.

Keep the renderer unchanged. Its two bounded candidates have no repeatable end-to-end gain. Retain actual hierarchy-render guards for colored/translucent content, cumulative fading, one sample pixel, and wide-color neighbors. Remove every temporary experiment flag, image dump, added delay, and format print.

## Design and implementation steps

These are case declarations and regression coverage, with no new architecture or public API. The existing pipeline and pseudocode in plan 03 apply. Swift sketches describe the intended calls, not compilation evidence.

1. Complete plan 03 and review its acceptance evidence. Remove temporary probes; save their scripts, source hashes, logs, captures, and negative results outside Git. Commit experiment findings and useful regression guards as groundwork.
2. Add explicit readiness parameters and move Onboarding's hook. Explain the synchronous sizing or layout-preserving artwork assumption beside each provider. Keep each model builder and all matrices unchanged. Commit the verified behavior change separately.
3. Run `./swiftformat --lint`, the framework regressions through `./test SnapshotKitTestingTests --no-generate`, and affected image suites through `./test --snapshots --record never --review --timings --no-generate --only Bundle/Suite`.
4. Run the complete image suite serially with `./test --snapshots --record never --review --timings --no-generate`. Reconcile the capture multiset, pixels, tiles, retries, test identities, and intended policy changes against plan 02. This includes MainTabs, PlanningRegionPicker, Root, and Flyover late-change adversaries.
5. Review the final diff independently under `code-review`, publish above PR #524 through `gh stack`, and verify isolated CI. Keep the plan checkpoint and STU-121 current; do not merge without user authorization.

## Acceptance

- Every accepted fixture has normal/candidate repeated controls and an independent later-capture oracle with unchanged dimensions and explained pixel differences. Inspect Onboarding artwork in a cold process.
- Final production declarations pass affected and full-image assertions without recording references or narrowing coverage. Framework guards preserve noise, quiet windows, timeout/starvation, cancellation, retries, and cleanup.
- Savings distinguish repeated focused capture/settle totals from test time and full-suite observations. Do not extrapolate renderer CPU percentages into wall-clock savings.
- No experiment flags, extra waits, dump code, or untracked user files enter the commits.
- Root/Device Layout owner-task cancellation, DevicesSettings overlapping start cancellation, and the additional PlacesYear hook remain explicit follow-up scope in STU-121; do not call the broader issue complete.

## Review and resume point

All five-family controls and the delayed oracle pass with 62 pixel-identical images. Review confirms explicit fixture eligibility, preserved final settling, and excluded Settings/native paths. Plan 03 is published. The explicit declarations and Onboarding hook move are implemented, independently reviewed, and published in PR #525 at `1ef9b92b7`. Focused, framework, full-image, and isolated-CI checks pass. This completion record changes documentation only. User authorization already covers execution; no additional approval is required.

## Implementation evidence

The five provider declarations now explicitly skip measurement settling, and Onboarding loads its existing artwork through `prepareForCapture`. No model construction, matrix, reference, final settle, or shared renderer code changed.

- `./test SnapshotKitTestingTests --no-generate --no-build`, after the clean-source guard rebuild: 163 functions in 30 suites pass; seven expected issues belong to four assertion/retry probes.
- `./test --snapshots --no-generate --record never --review --timings` with the five selected `--only` suites: 62 captures in five functions pass after rebuilding. Capture time is 35.899s, settle time 18.466s, and test phase 53.753s. All 62 measurements skip sampling; all 62 final content settles remain; no post-action call or retry remains in this selection.
- `./swiftformat --lint` for all six changed Swift files and `git diff --check` pass.
- Independent review of the consumer diff against `433450cba` and the complete PR against `2fd1cdfaa` found no blockers. It checked model lifecycles, helper forwarding, cutsheet panels, matrix preservation, and final settling. Full-suite and isolated-CI evidence are recorded below.

Final artifacts: `/private/tmp/stuff-settle-final-{guards,framework,focused,full}/`, with console logs alongside. The complete image suite passed using the rebuilt products. Raw artifacts and analysis are retained in the durable `snapshot-settle-improvements-results/local-{guards,framework,focused,full}/` directories identified in plan 03. Implementation and evidence review are complete; broader follow-ups remain in STU-121.

### Full local validation

At implementation `1ef9b92b70a925370f181215ce70888b126d7c71`, all 935 captures and 78 test functions pass without retries. The capture multiset matches the plan 02 baseline, allowing only the intended 62 explicit measurement-policy changes. Test identities, 4,797,647,739 pixels, 1,014 tiles, sizing, and final-settle policies match exactly. MainTabs, PlanningRegionPicker, Root, and Flyover late-change cases all pass. No reference was recorded.

| Metric | Plan 02 control | Implementation | Change |
| --- | ---: | ---: | ---: |
| Capture work | 778.670s | 760.788s | 17.882s saved (2.30%) |
| Test phase | 872.092s | 855.283s | 16.809s saved (1.93%) |
| Selected five families | 53.860s | 35.235s | 18.625s saved (34.58%) |
| Other capture work | 724.810s | 725.553s | 0.743s slower (0.10%) |
| Traced settling | 463.403s | 447.534s | 15.869s saved |
| Sampled settle calls | 1,265 | 1,193 | 72 removed |
| Immediate settle calls | 563 | 625 | 62 added |
| Sample passes | 6,066 | 5,756 | 310 removed |

Both full runs use `--review --timings --record never`; build and generation are excluded. This single full comparison validates coverage and agrees with the repeated focused experiment; it is not a repeated full-suite or CI wall-clock benchmark. The full suite passes existing references; only the selected experiment PNGs are claimed byte-identical.

All settling, including measurement, still costs 447.534s locally, including 326.818s in rendering and 108.067s in sleep. These operation times are components of settling, not additional capture work. The remaining costs and async/native readiness follow-ups stay in STU-121.

### Isolated CI verification

Manual CircleCI pipeline `a1f51e15-17d6-467a-8fc8-9ea612deb573` (#2526) runs the full gate at exact implementation `1ef9b92b7`. The automatic stacked-branch run was explicitly `not_run`, so the manual request uses the modern project and string-valued `manual_full_gate: "true"`. Existing GitHub CI run `44186048572` already covers the same head and is green; no duplicate dispatch was needed. All CircleCI build, unit, audience, and snapshot jobs pass. Workflow `e1adb427-f700-40ad-987d-b843e9fceef6` completes in 731s; that is workflow wall time, not summed worker time.

The four nonempty snapshot workers pass 935 captures and 78 functions in 71 suites; the fifth worker is explicitly empty. Capture and trace-policy multisets retain identities, geometry, tiles, final floors, quiet windows, and maximum budgets, allowing only the 62 measurement skips and ten removed post-actions. There are no retries. All 1,818 calls reconcile: 1,193 sampled and 625 immediate.

The selected families improve from 64.421s to 42.569s in this CI sample (21.852s, 33.92%). Other families are 86.755s slower. Total aggregate capture work rises from 1,055.576s to 1,120.479s, and snapshot-job wall time rises from 441.713s to 498.504s. This single cross-run comparison therefore does not establish an overall CI speedup. The repeated local experiment and the selected CI paths support the targeted change; overall CI timing remains variable in the observed runs.

Current aggregate CI settling is 609.889s: render 498.887s, sleep 93.893s, layout 5.379s, pixel checks 1.861s, and residual 9.867s. The renderer-color candidates were tested locally, not on CI. A matched CI color-format trial and sampling-frequency investigation remain explicitly open in STU-121; current evidence does not rule out those opportunities.

Original uploaded trace/capture JSONL, summaries, JUnit, real CI step output, source/assignment metadata, and verification are retained under `snapshot-settle-improvements-results/ci/`. Each worker's actual staging command passed `--require-complete`. The CI collector and root independently reconciled raw records, allowing only sub-nanosecond floating-summation differences. Successful CI does not upload complete Xcode logs or result bundles, so those are not claimed as retained evidence.

## Completion review and delivery

Independent review recomputed the local full-run inventory, trace policies, seven original late-change identities, result-bundle test identities, and timing table. It found no remaining blockers. The root independently checked CI JSONL against uploaded summaries and the complete local capture inventory; all checks agree.

Implementation `1ef9b92b7` and groundwork `433450cba` are published in [PR #525](https://github.com/kyleve/Stuff/pull/525), above [PR #524](https://github.com/kyleve/Stuff/pull/524). The final checkpoint is documentation-only and preserves the tested source. No references, tolerances, coverage, renderer defaults, or temporary probes changed. STU-121 stays In Review for the unmerged PRs and explicit remaining opportunities. No merge is authorized by this completion record.
