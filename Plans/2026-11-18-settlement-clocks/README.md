# What snapshot settlement waits for

## Checkpoint

The repository owner requested an investigation of snapshot settlement, including measurement, run-loop pumping, animation speed and alternative approaches. The [experiment](01-clock-and-readiness-trials.md) starts at [PR 531](https://github.com/kyleve/Stuff/pull/531), `956c210ee`. The root coordinates hosted trials and publication on `perf/snapshot-settlement-clocks`. Three investigators examine executor scheduling, animation timing and measurement eligibility. [STU-121](https://linear.app/kve/issue/STU-121) tracks the investigation.

## Requirements and review

US-01. A maintainer needs to know whether a long wait is actually progressing the UI, and how to reduce it. R-01 explains the two hosts, quiet proof, wall-clock floors and disabled animations with real traces. R-02 tests the proposed clocks with positive and negative controls. R-03 tests an alternative with a known readiness contract and checks independently delayed output. X-01 excludes global floor or tolerance reductions and updates to reference images.

Q-01 (closed for trial design). A synchronous pump, an asynchronous poll and Core Animation use distinct scheduling mechanisms. Compare them separately on the pinned runtime. Q-02 (closed for trial design). Existing late-changing Root and Settings evidence rules out globally sharing readiness between the two hosts. Examine equal viewports as a future reuse condition and test synchronous Calendar components separately from their task-driven parent.

Reviewed at `956c210ee` against the prior [renderer trials](../2026-11-17-snapshot-settling-investigation/README.md), current implementation, trace artifacts and source-owned fixture readiness. A green comparison alone can accept an early frame. Require exact decoded pixels on the chosen static subjects against both current and independently delayed controls. Implementation of the experiment is authorized by the ongoing optimization request.
