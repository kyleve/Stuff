# 02 — Recompare a previously rendered portrait

Status: complete. Delivered in [PR 540](https://github.com/kyleve/Stuff/pull/540). Depends on the verified native UncertainArrival frame produced by [01](01-state-and-scenario.md). [Overview and R-04](README.md).

## Experiment

Run a cold render and a warm request for the same static state. Treat reference comparison as a separate operation on both paths. Under a bounded local environment, declare inputs such as case, trait and size parameters, renderer code and environment. When inputs or runtime identity are unknown, fall back to rendering or explicitly reject reuse. Include a fresh regenerated comparison outside the reuse path and invalidate corrupt or missing artifacts. Change only the current expected image and prove a warm hit fails the reference assertion. Change a rendering input and prove it misses. Keep the live Locations transition checks independent of cache hits.

```swift
let frame = try cachedOrRendered(request, declaredInputs)
try assertImage(frame, currentReference)
try assertGeometry(frame, expectedSize)
```

## Acceptance and controls

Report actual render invocations, cold/warm results, bytes or normalized pixels and elapsed time for the bounded case. Distinguish an artifact replay demonstration from safe cross-PR reuse. Document incomplete dependencies and any rejected assumptions. The first eligibility boundary is a single immutable Banner fixture in a pinned experiment session. Capture a fresh actual PNG on misses through a real renderer callback. Key the full declared state, viewport, traits and renderer identity; never key on reference bytes. Verify an independent cold regeneration, rejection of tampered output, a changed fixture or trait, and a changed reference. For a persistent local replay, namespace storage to the verified input/build session and identify which further dependencies would be required for general cross-commit reuse. Retain the executable reproduction without a remote service or default-suite change. The matching native UncertainArrival frame from Plan 01 supplies the render callback.

## Results

The real UncertainArrival portrait supplied both image and geometry assertions. Two independent simulator test processes used a fresh experiment directory and the same compiled products. The second process opened both appearance variants with zero renders. The changed expectation was a reviewed Waiting image of the same dimensions. That assertion failed as intended, although the stored PNG and its key stayed identical.

| Lookup or control | First process | Second process |
| --- | ---: | ---: |
| Compute session identity and open manifest | 89.61 ms | 31.09 ms |
| First light request | 22.58 ms, rendered | 1.16 ms, reused |
| Repeat light request | 0.21 ms, reused | 0.15 ms, reused |
| Same request, changed expectation | 0.12 ms, reused | 0.11 ms, reused |
| First dark request | 15.22 ms, rendered | 0.29 ms, reused |
| Recompute light after substituting a valid dark PNG | 14.26 ms | 20.48 ms |
| Recompute light after deleting its entry | 13.52 ms | 14.00 ms |
| Independent fresh light render | 13.89 ms | 13.82 ms |

Lookup timings include entry verification and any rendering or writing on a miss. Image and geometry assertions run separately. The first process made four cache-path renders and one independent render. The second made two cache-path renders, both forced by the recovery controls, and one independent render. Both independent renders reproduced the warm PNG byte for byte. A second two-process trial confirmed the same render counts and correct rejections. Its cold light request took 23.00 ms and the next process reused it in 1.17 ms, with 90.28 ms and 32.50 ms respectively for session setup.

An initial run built the unit-test scheme between the two snapshot processes. The build replaced the signed host executable. Its changed digest correctly refused the saved session, even though the snapshot test binary still matched. The retained driver launches each scheme twice consecutively. It fingerprints the simulator, runtime, locale, time zone, viewport, traits, test executable, host executable and host debug library. The fresh directory scopes the two supported configurations to one checkout and build session.

**Decision.** Reuse one verified frame for geometry and image assertions. Persistent lookups work in the bounded experiment, but 31 ms of identity setup on the warm launch already exceeds an individual fresh render. This test did not establish a net CI gain or safe reuse across builds. Cross-build reuse would also need a complete dependency model for resources, fonts and the render environment. [STU-121](https://linear.app/kve/issue/STU-121)
