# 06 — Deliver the sampling experiment result

- Status: complete
- Depends on: [05](05-metal-and-sampling-experiments.md), complete and published in PR #527 at `1594ea543`.
- Shared context: [Overview](README.md), R-06, X-02–X-04, Q-06–Q-08.

## Outcome and refinement decision

Keep the existing UIKit sampler and cadence. Neither Metal adapter satisfies the local prerequisite; neither tested scheduling candidate establishes an end-to-end benefit beyond the controls. A negative experiment was explicitly allowed by this plan. There is no accepted content class requiring a maintained fallback selector.

This outline was refined after plan 05's final pair. Delivery consists of reviewed findings, complete prototype cleanup, and the separately requested overlap outline. No production behavior or public API changes are selected. The architectural diagram in plan 05 describes the rejected prototype boundary; the existing renderer remains the implementation.

## Delivery steps and acceptance

1. Retain every prototype revision, failed and successful run, raw images, crash reports, timing source, and limits outside Git. The session's `snapshot-metal-sampling-results/{metal,cadence,combination}/` directories contain that evidence.
2. Restore `SnapshotRenderingSupport.swift`, `CaptureConfiguredSnapshot.swift`, `SnapshotImageRendering.swift`, and `SnapshotRenderingSupportTests.swift` to the parent. Verify byte equality and confirm no Swift, reference, matrix, target, or tool change remains in the PR. `restored-source.json` records hashes against `75978860f`.
3. Review the complete diff and raw evidence independently. Validate plan links/statuses and `git diff --check`. No Swift formatting or new full iOS/CI gate is required for the resulting documentation-only diff. The experiments themselves executed 880 image assertions and 23 focused framework functions; rejected Metal probes retain their failures explicitly.
4. Publish the findings through `gh stack` in PR #527 above #525. Keep the issue In Review and preserve the new [overlap phase](https://github.com/kyleve/Stuff/blob/0f4fddcb4c8ba356f2349ad3b987bfb19a92ac29/Plans/2026-11-17-snapshot-settling-investigation/07-overlap-snapshot-work.md) as an outline. Verify the published head and documentation classification. Do not merge or claim a new speedup.

## Review and resume point

The root reviewed the negative-result refinement against the experiment criteria. The original source is restored and verified, and all raw evidence is retained. Independent final evidence review is complete with no blockers. The result is published as a ready-for-review PR #527 at `1594ea543b56396c2664d05249b3e432d3382ed3`, above #525. Plans 05–06 are complete as bounded negative results. Plan 07 remains separately selected planning work and requires refinement before any overlap prototype. This final checkpoint changes documentation only; no new full-suite or CI performance result is claimed.
