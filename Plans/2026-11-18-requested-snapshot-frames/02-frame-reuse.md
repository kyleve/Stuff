# 02 — Recompare a previously rendered portrait

Status: ready. Depends on a real immutable output from [01](01-state-and-scenario.md). [Overview and R-04](README.md).

## Experiment

Run a cold render and a warm request for the same static state. Treat reference comparison as a separate operation on both paths. Under a bounded local environment, declare inputs such as case, trait and size parameters, renderer code and environment. When inputs or runtime identity are unknown, fall back to rendering or explicitly reject reuse. Include a fresh regenerated comparison outside the reuse path and invalidate corrupt or missing artifacts. Change only the current expected image and prove a warm hit fails the reference assertion. Change a rendering input and prove it misses. Keep the live Locations transition checks independent of cache hits.

```swift
let frame = try cachedOrRendered(request, declaredInputs)
try assertImage(frame, currentReference)
try assertGeometry(frame, expectedSize)
```

## Acceptance and resume

Report actual render invocations, cold/warm results, bytes or normalized pixels and elapsed time for the bounded case. Distinguish an artifact replay demonstration from safe cross-PR reuse. Document incomplete dependencies and any rejected assumptions. The first eligibility boundary is a single immutable Banner fixture in a pinned experiment session. Capture a fresh actual PNG on misses through a real renderer callback. Key the full declared state, viewport, traits and renderer identity; never key on reference bytes. Verify an independent cold regeneration, rejection of tampered output, a changed fixture or trait, and a changed reference. For a persistent local replay, namespace storage to the verified input/build session and identify which further dependencies would be required for general cross-commit reuse. Retain the executable reproduction without a remote service or default-suite change. Root reviews and publishes. Resume execution after plan 01 produces a frame.
