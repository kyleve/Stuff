# 01 — Render a state and a sequence of named frames

Status: complete. Delivered in [PR 540](https://github.com/kyleve/Stuff/pull/540). Dependencies: none. [Overview and R-01–R-03](README.md).

## Experiment

Use the same real Flight Status Banner states and trait variants as the existing suite. Compare each of the 20 ordinary outputs to its committed reference, including dimensions, alpha and decoded pixels. Retain independent native annotations. Test a direct SwiftUI render first. If parity fails, identify the difference and try one single-host native approach, with an explicit successful draw. Report the number of frames eligible under each strategy. Deliberately change a label and a layout and check the corresponding assertions. An unsupported or incomplete render must remain visible as a failure.

In the hosted WhereUI tests, seed California into a real report behind a controlled first samples read. Mount Locations at fixed geometry, observe loading, release the read, observe the correct visible region, then activate the real card. Capture all three named frames with a visible state witness and checked draw completion. Retain the dimensions and visible semantic evidence beside the PNG. Compare independently prepared hosts at matching states after extra native display time. Verify that withholding delivery or selection prevents the requested milestone. Time waiting for semantic conditions separately from deliberate oracle waits. Try one corrective iteration if mount, geometry or readiness affects equivalence. Caller cancellation and failed captures must unwind the gate and host.

```swift
let portrait = render(flightCase, configuration)
try compare(portrait, currentReference)
try await withLocationsHost { host in
    capture(host, when: loadingIsVisible)
    await releaseData()
    capture(host, when: californiaCardIsVisible)
    activateCaliforniaCard()
    capture(host, when: selectionIsVisible)
}
```

## Acceptance and controls

Run the probes through the repo's `./test`, also exercising existing image and behavioral controls. Measure actual renders, mounts and intentional delays. A supported disagreement with the independent oracle is a valid outcome. Preserve executable probes and a local reproduction command in this folder. Keep the probes outside ordinary CI discovery. Root owns the one simulator and publication. Run two independent passes where the method completes. Check exact dimensions and normalized RGBA separately from ordinary comparison tolerances. A successful native draw must report completion. Verify the visible selection before and after the draw, with a fresh host as pixel oracle. Use the experiment suites in WhereUISnapshotTests and WhereUITests alongside WhereUISnapshotTests/FlightStatusBannerSnapshotTests, WhereUISnapshotTests/LocationsViewSnapshotTests, and WhereUITests/FlightReviewPresentationTests. Release pending store work on failure.

## Controls and first iteration

The control command used `./test --timings --review --record never --only WhereUISnapshotTests/FlightStatusBannerSnapshotTests --only WhereUISnapshotTests/LocationsViewSnapshotTests --only WhereUITests/FlightReviewPresentationTests` on Xcode 27.2, iPhone 17, iOS 27.2. Four image test functions passed and produced 76 captures. All four flight presentation tests passed. Two annotated Locations images had review differences within the ordinary comparison tolerance. Banner produced 22 images with zero settling samples. Locations produced 54 images, took 401 samples, and spent 35.571 seconds in final settling. Those suites cover more cases than either selected prototype.

The direct SwiftUI output had the right dimensions in all 20 cases. In UncertainArrival its bottom row was fully transparent where the native reference was opaque. In increased contrast, portions of its text retained the ordinary secondary color. The one-mount hosted path independently rebuilt the same production fixture and performed intrinsic fitting on its final host. A changed same-size flight state and extra padding each tripped the ordinary comparator. Existing accessibility annotations were exercised in the control run.

The first Locations sequence held the actual store read, released a seeded California day, and activated the visible California card. Loading and loaded were byte-identical to their fresh, independently delayed hosts. The selection title was already visible, yet 660,961 of 3,162,132 pixels differed (20.9%). The first frame cropped September while the delayed frame showed its legend and the settled navigation controls. Withheld data and a withheld card activation both prevented their corresponding milestones. The corrective trial requires a finished native transition, the visible year control, and the complete target month on screen. Its independent oracle retains the extra 600 ms display interval.

## Matched Banner measurements

Each backend rendered the same 20 ordinary state and environment combinations. The timer included building the production view, fitting its intrinsic height, drawing and encoding PNG. Each backend received one warm-up request. Reference access, disk export and image comparisons followed timing. Each trial ran in two test processes and reversed backend order on the second launch.

| Pass | Existing capture | Single native mount | Elapsed reduction |
| --- | ---: | ---: | ---: |
| Trial 1, existing capture first | 1.124 s | 0.411 s | 63% |
| Trial 1, single native mount first | 1.004 s | 0.437 s | 56% |
| Trial 2, existing capture first | 1.138 s | 0.391 s | 66% |
| Trial 2, single native mount first | 1.003 s | 0.451 s | 55% |

Every native output in all four passes was byte-identical to the production capture and its reviewed reference. The candidate mounted and drew exactly once per output. Both capture strategies already skip settling for these cases. SwiftUI's direct renderer repeated its own images consistently and failed the ordinary comparator for every one of them.

**Decision.** Fit and draw on the same native mount for this immutable Banner fixture. This is a candidate for a narrow production change covering ordinary immediate, intrinsic components. Accessibility annotations and stateful screens need their own equivalence evidence before extending eligibility.

## Locations after the correction

The selected frame requires the real California selection, its navigation title, an enabled Show Year action, at least one attached native navigation controller with no active transition, and the complete September card with its one-day California legend inside the safe viewport. One physical pixel of tolerance accounts for conversion between accessibility and UIKit coordinates at the safe-area edge. The same visible evidence is checked immediately before and after drawing.

Loading, loaded and selected PNGs were each byte-identical to the matching independent host in every corrected pass, including across test processes. Withholding either source event prevented the corresponding frame. Substituting the original mid-transition image into a copy of the outputs made the retained audit exit 1 and identify the selected frame.

| Final trial order | One host, three frames | Three fresh hosts, three frames | Deliberate display hold within fresh-host time | Fresh-host time less display hold |
| --- | ---: | ---: | ---: | ---: |
| One host first | 2.300 s | 3.741 s | 1.810 s | 1.931 s |
| Three fresh hosts first | 2.066 s | 4.438 s | 1.854 s | 2.584 s |

Times include real data delivery, rendering, PNG export and teardown. In the one-host sequence, the loading condition took 17–72 ms and the loaded condition took 49–66 ms **after** releasing data and completing refresh. Selection needed 1.07–1.11 s after activation. Its native draw then took 43 ms in one run and 478 ms in the other. These measurements distinguish visible readiness from the cost of the draw itself.

**Decision.** Expose loading and loaded as explicit events where the screen has a visible state to assert. Selection needs evidence of the completed visual transition. Sharing a host exercised the entire interaction and removed two mounts. The faster path reversed with run order after subtracting the independent controls' display holds, so this experiment does not establish a wall-time saving for the Locations suite.
