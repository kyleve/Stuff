# 01 — Render a state and a sequence of named frames

Status: ready. Dependencies: none. [Overview and R-01–R-03](README.md).

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

## Acceptance and resume

Run the probes through the repo's `./test`, also exercising existing image and behavioral controls. Measure actual renders, mounts and intentional delays. A supported disagreement with the independent oracle is a valid outcome. Preserve executable probes and a local reproduction command in this folder. Keep the probes outside ordinary CI discovery. Root owns the one simulator and publication. Run two independent passes where the method completes. Check exact dimensions and normalized RGBA separately from ordinary comparison tolerances. A successful native draw must report completion. Verify the visible selection before and after the draw, with a fresh host as pixel oracle. Use the experiment suites in WhereUISnapshotTests and WhereUITests alongside WhereUISnapshotTests/FlightStatusBannerSnapshotTests, WhereUISnapshotTests/LocationsViewSnapshotTests, and WhereUITests/FlightReviewPresentationTests. Release pending store work on failure. Resume with the simulator build and matched repeated measurements.
