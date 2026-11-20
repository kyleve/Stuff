# 03. Capture the native safe-area test immediately

Status: executing. Reviewed against main `9dd17d9b5`. This step can land independently of the other test optimizations.

## Outcome and verification

US-03 / R-03. A developer checking UIKit safe-area propagation should get the result as soon as layout applies the requested insets. The fixture uses plain parent and child view controllers. It reads the child's native insets while mounted, then checks the original frame and detached parent and view after capture.

1. Select `.immediate` in `fixedViewportPropagatesInsetsToNativeChildren`. The readiness hook only reads geometry and the test discards the image. Keep both inset overrides, three attachment states and two horizontal size classes.
2. Run `./test --only SnapshotKitTestingTests/SnapshotImageRenderingTests` on the branch. Require all six parameterized cases to pass with both widths. The adjacent native navigation-bar geometry test still exercises its settled capture at both accessibility settings.
3. Keep production rendering and image references outside this change (X-03). This existing capture-policy argument requires no new interface.

## Timing evidence

Four unprofiled runs on the same iPhone 17 simulator with iOS 27.2 bracketed the candidates with two runs of main. The safe-area test took 8.086 and 7.952 seconds with settling and 0.726 and 0.698 seconds with immediate capture. All four runs passed the same 90 selected tests. The means differed by 7.307 seconds per run. The merged-main unit job spent 8.410 seconds on this case. [CI job](https://app.circleci.com/workflow/865a46d1-c504-4ec7-9956-50af96876b4b/job/8c138db7-cde0-41c7-8b4b-28b79719cf1a)

## Verification on current main

On a fresh iPhone 17 simulator running iOS 27.2, `./test --skip-architecture --only SnapshotKitTestingTests/SnapshotImageRenderingTests` passed all five tests in 13.143 seconds. The native inset test passed all six cases in 1.035 seconds, exercising both widths in each case. The native bar settlement test passed both accessibility settings in 9.757 seconds. The architecture checks passed on the first invocation. Host checks and SwiftFormat lint also passed.

The native-insets implementation agent owns branch `perf/native-insets-immediate`. The primary agent owns completed-diff review and publication.
