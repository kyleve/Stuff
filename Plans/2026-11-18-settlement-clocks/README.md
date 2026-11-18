# What snapshot settlement waits for

## Checkpoint

The repository owner requested an investigation of snapshot settlement, including measurement, run-loop pumping, animation speed and alternative approaches. The [experiment](01-clock-and-readiness-trials.md) starts at [PR 531](https://github.com/kyleve/Stuff/pull/531), `956c210ee`. The root coordinated the hosted trials on `perf/snapshot-settlement-clocks`. Investigators checked executor scheduling, animation timing, measurement and full-resolution output. The Calendar change is on `0484d0016`. Independent review found and corrected a shared Flyover caller. The final measurement control reproduced the Settings clipping. The reviewed implementation and local evidence are published in [PR 532](https://github.com/kyleve/Stuff/pull/532). Full local and CI verification passed at `61a6df387`. The experiment is complete. [STU-121](https://linear.app/kve/issue/STU-121) tracks the investigation.

## Requirements and review

US-01. A maintainer needs to know whether a long wait is actually progressing the UI, and how to reduce it. R-01 explains the two hosts, quiet proof, wall-clock floors and disabled animations with real traces. R-02 tests the proposed clocks with positive and negative controls. R-03 tests an alternative with a known readiness contract and checks independently delayed output. X-01 excludes global floor or tolerance reductions and updates to reference images.

Q-01 (closed for trial design). A synchronous pump, an asynchronous poll and Core Animation use distinct scheduling mechanisms. Compare them separately on the pinned runtime. Q-02 (closed for trial design). Existing late-changing Root and Settings evidence rules out globally sharing readiness between the two hosts. Examine equal viewports as a future reuse condition and test synchronous Calendar components separately from their task-driven parent.

Q-03 (closed, November 18). Which Calendar components qualify for immediate layout? All 66 matched the ordinary references, but the full-resolution exports exposed tiny differences in the four month fixtures with visible planned-stay hatching. The ordinary control, repeated control and independently delayed host agree. Limit adoption to the 32 exact variants. Keep sampled settling as the default for new month fixtures. The [experiment](01-clock-and-readiness-trials.md) records the validation.

Reviewed at `956c210ee` against the prior [renderer trials](https://github.com/kyleve/Stuff/blob/f12cb58d8940a3e21b74e4d633a7bbe08044cb28/Plans/2026-11-17-snapshot-settling-investigation/README.md), current implementation, trace artifacts and source-owned fixture readiness. A green comparison alone can accept an early frame. Require exact decoded pixels on the chosen static subjects against both current and independently delayed controls. Implementation of the experiment is authorized by the ongoing optimization request.

## Outcome

The 32-fixture change cut the focused Calendar suite from 39.022s to 30.910s (20.8%). On CI the selected cases recovered 11.265s of final settling and the Calendar suite took 60.596s, down from 76.679s. A 100× layer clock accelerated explicit animations without a repeatable reduction in the measured suites. Shortening the async poll to 10ms traded 10% more renders for a 1.4% local gain. Measurement also exposed a correctness reason to draw. Settings produced the right height after one committed hierarchy draw and the wrong height after a matched delay. A late-loading fixture still required the ordinary readiness path. The [execution record](01-clock-and-readiness-trials.md) gives the timings, images checked and limits.
