# 05 — Cover every snapshot reference

Status: complete. Delivered in [PR 540](https://github.com/kyleve/Stuff/pull/540). Depends on [Plan 04](04-two-hundred-more.md). [Overview](README.md) · [STU-121](https://linear.app/kve/issue/STU-121)

## Scope

The user asked to continue through the rest of the suite and accepts small timing-related pixel changes. At `715fca929` there are 877 reviewed images. Plan 04 exercised 200 using the production renderer. Run the remaining 677 on that same harness. Of those, 585 have never been tried and 92 have only been tried with the earlier component prototype. Keep the three groups distinct when counting coverage or interpreting timings.

Use the checked-in subject, device, Dynamic Type, theme, geometry, animations, actions and asynchronous fixture readiness for each image. The experiment covers captures of web content, fixed viewports, annotation legends, long scrolling screens and theme comparison sheets. Preserve ordinary capture defaults and all reference files.

## Method

Run each selected test method on one pinned simulator under baseline, retained and early capture, then in reverse order in fresh processes. Each output must identify its actual native mounts, ordinary reference verdict and geometry. Count composite images once and account for each rendered panel separately. The two baseline passes distinguish ordinary runtime variability from candidate changes. Reuse Plan 04 evidence on the 200 disjoint paths after verifying the capture behavior on that cohort is unchanged.

```swift
let host = try await measureIfNeeded(subject, configuration)
let frame = try await capture(subject, retaining: host, policy: arm)
compareWithReviewedReference(frame)
```

The existing [hosting diagram](README.md#design) and Plan 04 describe the ordinary path. For measured annotations, mount the annotation container during measurement and keep that wrapper on screen through capture. Upstream annotation rendering can temporarily reparent the subject for tiles over 2,000 points. The mount metric counts attachments of the outer wrapper to the test host. Fixed viewports already mount once and serve as controls. Retain declared measurement readiness, preparation and action hooks, annotation parsing, insets and explicit minimum waits. The earlier draw applies only to eligible ordinary content.

Freeze the [manifest](mount-remaining.txt) before measuring. Validate the partition against Git and the previous two selections. Treat a capture error, missing artifact, threshold failure, dimension mismatch, and visually incomplete content as distinct outcomes. Preserve genuine failures and the input that produced them. Investigate and retry interrupted processes or incomplete exports. Inspect substantive deltas against both live controls, including comparisons accepted by the ordinary policy. Check changed legends, material, controls, scroll position, text and asynchronous loading at native resolution. Record elapsed capture time and local test-phase time separately.

## Execution and acceptance

1. Review the manifest, exact method selections, reuse of earlier evidence and annotation-host lifecycle. Record decisions and limitations.
2. Extend the opt-in capture path and launcher. Exercise fixed and measured annotations with the ordinary lifecycle, including cleanup on failure.
3. Run the six comparisons. Audit exported paths, native timings, panel identities, mount counts, ordinary verdicts, dimensions, decoded pixels and repeatability. Summarize outcomes across all 877 identities and retain reproducible per-image results.
4. Document which cases benefit, which need their existing waits or host, and where the two orders disagree. Verify the default harness and publish on the existing experiment PR. Root owns the launch and result reconciliation. Separate reviewers inspect the source and native images.

The November 18 review against `715fca929` verified all 677 selections across 62 methods, their disjoint union with Plan 04, the ordinary assertion route for WebKit, and the typed fixed/annotation paths. Running just the owning methods avoids a second test that deliberately exercises a reviewed Device Layout Lab identity. The fidelity review added the upstream tiling distinction and a tall annotation smoke capture.

## Reproduce

From the repository root, run the existing 200-image experiment once and supply its printed output directory to the remaining comparison. An existing complete Plan 04 output directory can be reused.

```sh
Plans/2026-11-18-requested-snapshot-frames/run-200
Plans/2026-11-18-requested-snapshot-frames/run-200 --remaining --include-200 /path/to/first-output
```

The second invocation produces a per-reference CSV, a full JSON report and the raw images from all six remaining-cohort runs. The CSV records the policy, timing, reference verdicts, decoded comparisons and repeatability per file. The six-bundle timings are sums across the two independently run cohorts. Individual test-phase times apply to their actual launches.

Before the full run, five selected references passed their ordinary comparison using the new build. Each of the six native captures attached its outer wrapper once. The 2,202 × 10,326 Day Relabel annotation reproduced the reference PNG byte for byte. The smoke run also exercised both panels of an annotated Region Summary sheet, a fixed annotated Main Tabs viewport, an InstallerKit card and a WebKit page.

The reverse early run rejected four installer-site images that had passed the forward early run. All four had the expected dimensions. On the Rebuilding iPhone page, the last 4,539 rows of the 7,611-pixel image were filled with one background color. The release notes, installation information and footer disappeared. We followed up on all 24 WebKit references in four fresh processes in early, retained, retained, early order. Their times are separate from the main trial. Each focused output is compared with the live production controls.

The focused WebKit repeat uses the same snapshot build. Each directory contains the actual PNGs, ordinary comparison verdicts, timings and test log for that process.

```sh
web_output=$(mktemp -d)
for entry in 1-early 2-retained 3-retained 4-early; do
  target="$web_output/$entry"
  mkdir -p "$target"
  TEST_WORKDIR="$target/test" \
  TEST_RUNNER_SNAPSHOT_MOUNT_TRIAL="${entry#*-}" \
  TEST_RUNNER_SNAPSHOT_MOUNT_MANIFEST="$PWD/Plans/2026-11-18-requested-snapshot-frames/mount-remaining.txt" \
  TEST_RUNNER_SNAPSHOT_MOUNT_OUTPUT="$target/images" \
    ./test --no-generate --no-build --skip-architecture --skip-host-tests \
      --timings --record never --only 'ToolsSnapshotTests/InstallerSiteSnapshotTests/site()'
done
```

## Measured results

Each of the 877 reviewed files has a row in the [per-image results](suite-images.csv). The first columns show eligibility, each candidate’s pixel difference against live controls and mean capture seconds saved. The remaining columns contain the individual ordinary verdicts, timings and repeat comparisons. The full JSON and PNGs are emitted by the reproduction command.

| Capture policy | 677-reference run, forward / reverse | All 877, summed forward / reverse | Outer mounts per complete pass |
| --- | ---: | ---: | ---: |
| Production | 500.6 / 503.2 s | 644.8 / 648.6 s | 1,742 |
| One mount, declared waits | 500.4 / 503.5 s | 644.1 / 646.9 s | 934 |
| One mount, eligible early draw | 418.1 / 419.0 s | 518.3 / 520.4 s | 934 |

With early capture, all 877 references took **126.5 / 128.2 seconds less** than production (19.6% / 19.8% in forward / reverse order). Final settlement fell from 336.9 / 338.7 seconds to 208.8 / 209.3 seconds. The 431 files that actually took a shorter final wait went from 305.1 / 307.3 to 179.0 / 180.0 seconds. The 126 fixed-viewport files already attach once. All 97 accessibility annotations keep their ordinary readiness, including nine two-panel sheets.

| Pixel-exact to the live production control | Forward | Reverse | Exact in both orders |
| --- | ---: | ---: | ---: |
| Retained with declared waits | 868/877 | 865/877 | 859/877 |
| Retained with eligible early draw | 828/877 | 820/877 | 815/877 |

The conservative opt-in covers **404 of 431 eligible images**. It keeps the declared wait for the 24 WebKit pages, the Flyover list and the two AX5 Presence Timeline toolbar images. Summing the measured early times for the opt-ins and production times for the rest projects **118.3 / 119.7 seconds saved** per pass, or 18.4% / 18.5% of the full capture workload. The measured runs used one policy per process. This mixed rollout is a projection. A rollout requiring pixel equality in both orders could opt in 362 of those files, for a projected 103.6 / 104.7 seconds saved.

Across all 934 native captures per pass, including the separate panels of 57 sheets, retention removed 808 extra wrapper attachments. The 86 measured annotations used one outer wrapper apiece for each native capture. The other 11 annotated files already used a fixed viewport. Of the 97 annotated images, 96 were pixel-identical to both controls. The remaining timeline annotation differed from the reverse production control on 40 pixels by 1/255 per channel. All sheet geometry and all image dimensions matched.

All 877 files passed the ordinary comparator in both production and declared-wait retained passes. Across both orders, the 18 retained files with any pixel differences all stayed within 2/255 per channel. In the early arm, 815 files matched both controls exactly, 55 more differed by at most 2/255, and seven showed visible changes. Three passed the comparator despite those changes. Four WebKit captures failed it in one order. The two production baselines themselves were pixel-identical on 868/877 files.

The 585 newly tested files alone took 486.6 / 489.1 seconds at baseline and 407.6 / 408.6 with eligible early drawing. All 92 fixtures from the simpler component prototype reproduced their live production PNGs with declared waits on the production harness in both orders. Early drawing introduced 1/255 drift on eight hatched calendars. The full renderer keeps the rest of the production pipeline. Its retention-only timing on the 92 was 14.1 / 14.1 seconds, close to 14.0 / 14.2 for production.

The measured test phases, which include comparison, export and test-runner overhead, took 554.5 / 558.6 seconds at baseline versus 478.1 / 482.7 seconds early for the 677 files. Adding the two corresponding 200-file runs gives 737 / 742 seconds versus 618 / 624 seconds, roughly 16% less. These were separate local launches on the same simulator and exclude setup and compilation.

## Interpreting the exceptions

The iPad Flyover list and the two largest-text Presence Timeline images pass the ordinary image comparator even when early capture changes visible content. In the list, a loading indicator replaces the Widget preview. In the populated timeline, the native calendar-and-clock toolbar symbol grows from 78 × 64 to 93 × 77 pixels and its badge moves. The surrounding button, timeline rows and text stay in place. The early symbol reproduces on iPhone and iPad in both processes. Keeping the final settle reproduces the settled symbol. [Flyover evidence](04-two-hundred-more.md#what-the-pixels-caught) · [Timeline toolbar](../../Where/WhereUI/Sources/Primary/PresenceTimelineList.swift)

The installer site's DOM readiness hook waits for navigation, fonts and paint frames. All four failed images had the same dimensions as their controls, with late page content missing. On iPhone, the missing region begins at 3,072 pixels, corresponding to 1,024 points at 3×. The harness draws native tiles of up to 2,000 points. The images establish where painting stopped. The specific cause inside WebKit remains unverified. [WebKit readiness](../../Shared/SnapshotKitTesting/Sources/SnapshotWebPage.swift) · [Native capture](../../Shared/SnapshotKitTesting/Sources/TileAndStitch.swift)

Both focused early processes rejected 2/24 images. The first lost lower-page content on Missing Details iPhone and Rebuilding iPhone. The last lost it on App iPhone dark and Channel iPad dark. Both intervening retained processes matched all 24 live production pages exactly. Across the four early processes, eight of 96 web captures failed, spanning six distinct references. The main suite's four affected identities and the two additional follow-up identities shared this failure mode. Keep the final wait for the whole WebKit group. The separate 96 diagnostic captures do not contribute to the suite timing totals.

## Verification

An independent review against stack base `e479fa140` and previous prototype `715fca929` matched all 5,604 native capture identifiers with the raw simulator logs and compared all 5,262 exports. Both source cohorts used the same simulator UDID and the 200 earlier files all used the unchanged ordinary renderer paths. There were zero capture retries in the measured trial. A temporary copy that changed both the measured annotation’s trace and its sidecar to report one baseline attachment failed the audit. Combining overlapping source inventories also failed.

With the experimental flags absent, 165 shared harness tests and the two ordinary Day Relabel and Region Summary methods passed. The latter produced 64 native captures. The shared harness exercised seven expected issues in its assertion and retry tests. With early capture enabled, 28 focused tests passed across the measurement hook, capture preparation, annotation and large-view suites. These include subject identity while measuring and preparing, cleanup after a throwing annotated measurement, and tall-view tiling. SwiftFormat, Ruff, architecture checks and `git diff --check` passed.
