# Test the current snapshot releases

Status: complete. Requirements: [R-01 and R-02](README.md#scope-and-questions). The timed runs used the published tracing implementation from [PR 524](https://github.com/kyleve/Stuff/pull/524). The accepted updates are in [PR 539](https://github.com/kyleve/Stuff/pull/539).

1. Compare tagged changes with the calls made by SnapshotKitTesting. Check the versions Xcode actually built for both treatments.
2. Run Settings, Developer Overlay, Planning Region Picker and the Installer Update Failure Card serially on the same simulator. Enable timings and pixel review and disable recording. These fixtures cover intrinsic measurement, native chrome, delayed content, accessibility annotations and a small component.
3. Test both latest stable releases together. If a new annotation design changes reference pixels, isolate the maintenance update that retains the existing design. Keep usable bug fixes if they pass compatibility checks. Regenerate attribution for accepted packages and check full image coverage before retaining a shared rendering change.
4. Compare measurement and content settling, retries and visual differences separately from accessibility parsing and reference comparison. Repeat a matched treatment before attributing a speedup. Document a negative result if the package code and run do not support a settling improvement.

Restore rejected pins after each trial. Keep the analysis and accepted package updates together on the independent branch.

The fixed-reference trial exposed the regression addressed by Cash App's [tiled accessibility fix](https://github.com/cashapp/AccessibilitySnapshot/pull/357). In the 3,426-point Day Relabel screen, the reference collapses the numbered highlights at the origin, while the maintenance release places them on the controls. The paired ordinary view still passes. Record only this verified correction in a separate run, repeat its assertion, and leave all other references in place.

## Upstream and local ownership

The original build used swift-snapshot-testing 1.19.3 and AccessibilitySnapshot 0.12.0. The latest stable tags checked on November 18 were 1.19.7 and 0.13.1. The build log for each run confirms the actual Xcode resolution.

- Point-Free changed recording API deprecations, assertion diagnostics, watchOS compilation and perceptual comparison on macOS 27. Our capture pipeline invokes the package to compare and record a finished image. [Changes from 1.19.3 to 1.19.7](https://github.com/pointfreeco/swift-snapshot-testing/compare/1.19.3...1.19.7) · [Local comparison](../../Shared/SnapshotKitTesting/Sources/AssertSnapshotReference.swift)
- Cash App restored the view hierarchy after tiled drawing in 0.12.1. Version 0.13 moved accessibility badges and changed legend sizing. We instantiate that SwiftUI annotation renderer. The cutoff remains 2,000 points in either dimension. [Renderer changes](https://github.com/cashapp/AccessibilitySnapshot/compare/0.12.0...0.13.1) · [Local wrapper](../../Shared/SnapshotKitTesting/Sources/AccessibilitySnapshotViewController.swift)
- Our own UIKit loop performs the layout, hierarchy draw and pixel stability check, including the 250 ms floor. Annotated views run Cash App's parser after the content settles. A raised floor can request a preliminary parse and a separate preparation settle. Neither release adds a completion signal for these waits. [Settle loop](../../Shared/SnapshotKitTesting/Sources/SnapshotRenderingSupport.swift) · [Capture stages](../../Shared/SnapshotKitTesting/Sources/SnapshotImageRendering.swift)

## Compatibility evidence

On the same iPhone 17 simulator and iOS 27.2, four suites produced 41 distinct captures, 42 tiles and 213,850,962 pixels per treatment. In each run the same 38 measurement calls and 41 content calls reached a settled verdict. The build and test commands used the four selectors in step 2 with `--timings --review --record never`.

Both latest packages together changed all five annotated images in the selected suites. The other 36 matched byte for byte. In the Installer card, the numbers visibly move from the left to the right edges of their highlighted controls. Settings and Planning Region Picker also changed. The assertions failed on five images across three suites. The failed run timed all 79 calls but is excluded from performance comparisons.

The maintenance combination (1.19.7 and 0.12.1) matched all 41 original images byte for byte. The separate Day Relabel run exposed the tall-view fix. All seven other Day Relabel images matched; 11,116,006 of 22,737,852 pixels changed in its annotation. Two independent captures produced identical failure attachments. The newly recorded reference decodes to the same pixels as the first capture. The `--record failed` run updated exactly one LFS image.

## Timing result

The four runs below used PR 524's tracing, the same simulator, fixtures and reference images. Each built its intended package versions and passed the four suites with 79 settled calls and byte-identical captures. Test-body time sums the four Swift Testing suite durations. Test-phase time includes launching the two bundles and Xcode's result handling.

| Run | Measurement settle | Content settle | Total settle | Suite bodies | Test phase |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original packages, first run | 11.381 s | 11.828 s | 23.209 s | 31.294 s | 44.647 s |
| Updated packages, first run | 11.272 s | 11.663 s | 22.934 s | 30.788 s | 46.512 s |
| Updated packages, second run | 11.371 s | 11.599 s | 22.970 s | 30.728 s | 46.100 s |
| Original packages, second run | 11.272 s | 11.646 s | 22.918 s | 30.763 s | 44.009 s |

The 0.111 s difference between mean settle times is smaller than the 0.291 s spread between controls. The updated runs averaged 1.978 s longer across the entire test phase. The suite bodies differed by 0.271 s on average, in the opposite direction. These local runs do not support a settling or end-to-end speedup. The package update is justified by the tiled annotation fix.

## Delivery checks

The [implementation](https://github.com/kyleve/Stuff/commit/3d6b03b876a47283c948b2ea1d858aa112f9d20e) builds directly on `main` at `1678df612`. Both Xcode build logs resolve swift-snapshot-testing 1.19.7 and AccessibilitySnapshot 0.12.1.

- `./test --only SnapshotKitTestingTests` passed all 159 tests in 29 suites. Swift Testing recorded seven expected issues. The normal architecture and host checks passed.
- `./test --no-generate --skip-architecture --skip-host-tests --snapshots --review --timings --record never` passed 80 tests and 979 captures in 768.419 seconds with zero retries. The Day Relabel suite matched all eight references byte for byte, including the corrected annotation. Across the suite, 171 comparisons reported different PNG bytes. Of those, 131 had differing pixels within the existing tolerances.
- `./attribution --check`, `./swiftformat --lint Package.swift` and `git diff --check` passed. SwiftPM changed only the two selected pins. The generated report changed those two development-tool versions.
