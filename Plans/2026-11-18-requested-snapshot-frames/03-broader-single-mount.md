# 03 — Try one native mount on more production views

Status: ready. Depends on the byte-exact Banner renderer delivered by [01](01-state-and-scenario.md). [Overview and R-05](README.md).

## Question and scope

Does measuring and drawing on one native mount reproduce more of the suite, and how much faster is it on equal inputs? The user requested a broader trial after reviewing the Banner result. A positive result supports adoption only for the cases tested. A reproducible failure or slower result also answers the question.

Exercise existing ordinary, single-subject, known-width intrinsic fixtures without hooks. Use the same production builders, source paths, reference groups, traits and identifiers as the original suites. Inventory before running: 20 Banner controls, 26 widget images from five families, 36 calendar frames including month views and day or badge grids, four Year mode picker images, and six InstallerKit failure cards. Of these 92 requests, 74 already use immediate capture and measurement; 18 have a production settling policy. The six InstallerKit images include a Dynamic Type variant taller than the device viewport. Accessibility annotation, full-content, fixed-frame and comparison-sheet rendering each use a different contract. Keep their original paths and count their exclusions. R-05 requires a result for every eligible request in both processes.

## Method

1. Run the nine owning suites through `./test --review --timings --record never`. Keep the original published plan and reference PNGs.
2. For each request, run the existing PNG renderer with its declared policy and the retained one-mount renderer. For requests that normally settle, add a control using the existing renderer with immediate measurement and capture. The two immediate arms separate the cost of the simpler host path from changing readiness. They still differ in other host setup.
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
