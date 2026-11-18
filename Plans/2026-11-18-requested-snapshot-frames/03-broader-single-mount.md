# 03 — Try one native mount on more production views

Status: complete. Delivered in [PR 540](https://github.com/kyleve/Stuff/pull/540). Depends on the byte-exact Banner renderer delivered by [01](01-state-and-scenario.md). [Overview and R-05](README.md).

## Question and scope

Does measuring and drawing on one native mount reproduce more of the suite, and how much faster is it on equal inputs? The user requested a broader trial after reviewing the Banner result. A positive result supports adoption only for the cases tested. A reproducible failure or slower result also answers the question.

Exercise existing ordinary, single-subject, known-width intrinsic fixtures without hooks. Use the same production builders, source paths, reference groups, traits and identifiers as the original suites. Inventory before running: 20 Banner controls, 26 widget images from five families, 36 calendar frames including month views and day or badge grids, four Year mode picker images, and six InstallerKit failure cards. Of these 92 requests, 74 already use immediate capture and measurement; 18 have a production settling policy. The six InstallerKit images include a Dynamic Type variant taller than the device viewport. Accessibility annotation, full-content, fixed-frame and comparison-sheet rendering each use a different contract. Keep their original paths and count their exclusions. R-05 requires a result for every eligible request in both processes.

## Method

1. Run the nine owning suites through `./test --review --timings --record never`. Keep the original published plan and reference PNGs.
2. For each request, run the existing PNG renderer with its declared policy and the retained one-mount renderer. For requests that normally settle, add a control using the existing renderer with immediate measurement and capture. The two immediate arms remove timed settling from the comparison. The existing immediate policy still yields and lays out, and the existing path manages window geometry, wrapping and capture differently. The paired result measures the whole capture path.
3. Build a fresh production subject for each arm, warm each renderer, time through encoded PNG, and do image comparisons outside the timer. Reverse renderer order in a second test process. Record capture errors, dimensions, encoded identity, pixel equivalence and the ordinary image assertion. Compare the candidate to both the live control and the reviewed reference. Review disagreements individually and retain the images beside the machine-readable output.
4. Report absolute timings and paired changes separately for already-immediate, normally settled and previously measured Banner requests. Inspect both repetitions, check coverage against the reference inventory, and distinguish inherited baseline drift from a new rendering difference. When a counterexample identifies a specific fix, try a bounded correction and repeat the affected comparisons.

The same opt-in launcher used by plans 01–02 installs probes in the two image bundles. Preserve the original reproduction command, run the trials serially, and verify ordinary discovery after cleanup. The existing Banner/Locations/cache experiment remains reproducible. This trial changes experiment code only.

The comparison uses the following per-request structure. The existing design diagram in the overview shows where the current expectations enter.

```swift
let production = try await capture(request, readiness: request.readiness)
let native = try drawOnOneMount(request)
if request.waitsForSettlement {
    let immediateControl = try await capture(request, readiness: .immediate)
    compare(native, immediateControl)
}
compare(native, production, reviewedReference)
```

## Acceptance and ownership

The fixture investigators own registrations in WhereUI and InstallerKitUI. The renderer investigator owns the shared Swift experiment. Root owns the launcher, simulator, independent artifact checks, results and publication in [PR 540](https://github.com/kyleve/Stuff/pull/540). [STU-121](https://linear.app/kve/issue/STU-121) tracks the decision. Close Q-04 with an eligibility recommendation and any observed exception.

## Production control

On iPhone 17, iOS 27.2, the nine owning suites passed 11 test functions and logged 138 timed captures. The original suites also exercise cases outside the matrix. Two full-screen calendar PNGs used different encoded bytes while comparing identically pixel for pixel. The branch contains 877 reviewed reference PNGs across six bundles. The matrix covers 92 of those files; elapsed time below applies to the measured inputs.

```sh
./test --review --timings --record never \
  --only InstallerKitUISnapshotTests/UpdateFailureCardSnapshotTests \
  --only WhereUISnapshotTests/FlightStatusBannerSnapshotTests \
  --only WhereUISnapshotTests/TodayWidgetViewSnapshotTests \
  --only WhereUISnapshotTests/YearTotalsWidgetViewSnapshotTests \
  --only WhereUISnapshotTests/TodayInlineAccessoryViewSnapshotTests \
  --only WhereUISnapshotTests/TodayCircularAccessoryViewSnapshotTests \
  --only WhereUISnapshotTests/YearTotalsRectangularAccessoryViewSnapshotTests \
  --only WhereUISnapshotTests/CalendarContentViewSnapshotTests \
  --only WhereUISnapshotTests/YearViewSnapshotTests
```

## First trial and corrective iteration

The first process reproduced 84 of 92 reference PNGs byte for byte. The eight exceptions were the light and dark versions of Itinerary, ItineraryOverlap, FocusedPlannedStay, and MultiRegionPlannedStay. Each passed the ordinary image comparison. An independent decoded-pixel comparison found 3–919 differing pixels per image, at most one channel level out of 255, with identical alpha and dimensions. The production control reproduced the references exactly. Forcing that same control to capture immediately also introduced small differences. The calendar fixture documents that planned-stay hatching needs a settled draw.

In the reversed pass the native Year picker also differed across its four variants. At accessibility size, 51,937 of 751,338 pixels (6.91%) changed, with a maximum channel delta of 78/255. The rim and shading of the glass changed while the labels and dimensions remained aligned. The ordinary comparator still accepted it. The existing renderer set to immediate reproduced that reviewed image.

The corrective trial adds a fourth arm to these twelve requests. It keeps the component attached through intrinsic fitting and a normal final content settle, then draws it on the same host. Measure the exact pixels and elapsed time against the original production capture, retain the immediate arms, and repeat in reversed order. The existing eligibility and reference inventory apply to this iteration.

| Initial trial, summed capture time | Production first → one mount | One mount first, shown as production → one mount |
| --- | ---: | ---: |
| 20 Banner controls, already immediate | 1.093 → 0.400 s | 1.064 → 0.434 s |
| 26 new widget images, already immediate | 0.905 → 0.225 s | 0.817 → 0.295 s |
| 28 new calendar images, already immediate | 2.055 → 1.111 s | 1.997 → 1.227 s |
| All 54 new images with matched immediate policies | 2.960 → 1.335 s | 2.814 → 1.521 s |

All 54 new immediate requests matched the reviewed PNGs byte for byte. For the six InstallerKit cards, the three-arm times were 3.568 / 0.252 / 0.111 s and 3.496 / 0.321 / 0.132 s (declared production / forced-immediate production / single mount). All three paths reproduced the six references, including the 1,206 × 2,728 image. The large difference between the two production timings comes from the change in readiness.

## Correction and decision

On the final two passes, the same 54 additional immediate images remained byte-identical. The paired sums were 2.969 → 1.329 s and 2.795 → 1.513 s. Across four passes this is a **46–55% reduction** for these 54 captures. Every Banner and every InstallerKit reference also matched on all four passes. The timing measures building, fitting, drawing and encoding each request. Suite launch, comparison and disk output are outside the timer.

| One mount with the declared final settle | First process: production → one mount | Second process: production → one mount | Byte-identical to reference, first / second |
| --- | ---: | ---: | ---: |
| 8 planned-stay calendar images | 2.773 → 2.471 s | 2.902 → 2.491 s | 1/8, 0/8 |
| 4 Year picker images, one-second floor | 4.198 → 4.112 s | 4.147 → 4.167 s | 0/4, 0/4 |

All 12 passed the ordinary perceptual comparison in both arms and both orders. The remaining calendar differences on the settled single mount were at most 1/255 per channel. The largest-text Year picker still differed over 52,764 pixels, with maximum channel delta 78/255, in **both** settled single-mount captures. The existing renderer, even forced to immediate, reproduced its reviewed PNG. The wait alone therefore does not explain the glass result. These data do not isolate which host difference causes it.

**Adoption boundary.** The 20 Banner controls and 54 additional already-immediate images support an opt-in fast path for those fixtures. For the six InstallerKit cards, testing a fixture-only move to immediate readiness would recover most of the cost while retaining the existing renderer. Keep the original rendering path for the eight hatched calendars and four Year pickers when exact pixels matter. Fixed frames, full-content screens, annotations, hooks, and cutsheet panel capture need separate evidence. The 92 files in this trial represent about 10.5% of the branch's 877 references.

**Verification.** Reproduce with `Plans/2026-11-18-requested-snapshot-frames/run-prototype --mount-matrix`. Each pass covered 92 selected references and accounted for all 41 excluded references in the nine registered suites. Auditing cross-checked the source references, output digests, dimensions, all arm orders, and the images saved for disagreements. Dropping a measured row or changing its recorded digest in a temporary copy failed validation. Independent decoded-pixel review distinguished the one-level hatching drift from the material change.

The original `run-prototype` command also passed both processes after the shared renderer refactor. Its 20 Banner references matched, cache controls passed, and loading, loaded and selected Locations frames matched their independent delayed hosts in both orders.
