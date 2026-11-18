# Adopt AccessibilitySnapshot 0.13.1

Status: complete. This follows the [dependency trial](01-dependency-trial.md). The user approved the changed SwiftUI annotation style after the timing experiment. Its original measurements and references remain the record of that experiment.

1. Resolve the latest stable AccessibilitySnapshot release and regenerate attribution. Verify the actual Xcode package graph and keep other package revisions fixed.
2. Refresh the tracked accessibility annotations in the WhereUI and InstallerKitUI suites. Select references by their configuration suffix. Keep ordinary images available for comparison. Check each changed image for affected badges, legend layout and unrelated drift. Verify cutsheet panel identities and review the tall Day Relabel annotations.
3. Run the framework tests with their normal recording defaults and the full image suite with recording disabled. Publish the dependency change, reviewed references and results together in [PR 539](https://github.com/kyleve/Stuff/pull/539).

## Reference review

SwiftPM and Xcode resolved AccessibilitySnapshot 0.13.1. Relative to the first trial, only that package pin and its development-tool credit changed. The recording pass selected the 99 checked-in `*_accessibility.png` files across 46 suites. All 99 produced new images. The 803 other references remained available for ordinary assertions. The recording run reported exactly the 99 expected new-reference notices.

Review covered 88 single images and 11 comparison sheets. All 99 had changed pixels, 93 kept their dimensions and six grew vertically by 38–205 pixels as their legends wrapped. The taller references cover two Flight Status Banner cases, Privacy Passport, Region Welcome and two Year Totals widget cases. All sheets retain their panel identities, labels and order. The two taller sheets also retain valid, nonoverlapping panel bounds. The 3,426-point Day Relabel view retains its aligned highlights and all 65 legend entries.

The largest difference was the standard iPhone Locations image. Its Estimated Time card now shows the region-outline artwork also present in the ordinary iPhone image and both iPad annotations. The 0.12.1 control had already passed with 22.63% differing pixels against the old reference. The new capture differs in 22.83% of pixels, and changes above the control's maximum channel delta are confined to the badge bands. The entire legend is pixel-identical. The recording-disabled run reproduced the new iPhone and iPad Locations annotations byte for byte.

## Verification and performance baseline

On the iPhone 17 simulator running iOS 27.2, `./test --no-generate --no-build --skip-architecture --skip-host-tests --snapshots --timings --review --record never` passed 80 tests and 979 captures in 764.075 seconds with zero retries. All 99 annotated references reproduced pixel for pixel. Eleven had different PNG bytes with identical decoded pixels.

`./test --no-generate --only SnapshotKitTestingTests` passed all 159 tests in 29 suites with seven expected issues. The normal architecture and host checks, manifest formatting, attribution drift check and independent diff review passed.

The run spent 350.650 seconds in capture settling (50.0% of summed capture time), 110.358 seconds in intrinsic measurement (including its own settling), and 9.321 seconds in accessibility parsing. Locations and MainTabs had the highest capture-settling totals at 35.663 and 35.134 seconds. These local figures provide the baseline for the next settling experiment.

Four Timeline fixtures (`InterruptedStay`, `Flights`, `UncertainArrival` and `Itinerary`) spent 6.408 seconds in measurement across 18 captures and another 5.722 seconds settling the final view. Seven neighboring fixtures already use immediate measurement. A focused experiment can test whether those four also reach the correct height immediately, keeping the final settle and checking cold and delayed captures for matching pixels, dimensions and scroll position.
