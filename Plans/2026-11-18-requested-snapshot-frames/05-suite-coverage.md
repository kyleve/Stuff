# 05 — Cover every snapshot reference

Status: executing. Depends on [Plan 04](04-two-hundred-more.md). [Overview](README.md) · [PR 540](https://github.com/kyleve/Stuff/pull/540) · [STU-121](https://linear.app/kve/issue/STU-121)

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
