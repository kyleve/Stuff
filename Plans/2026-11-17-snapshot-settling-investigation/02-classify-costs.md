# 02 — Classify measured costs

- Status: ready
- Depends on: [01](01-settle-tracing.md).
- Shared context: [Overview](README.md).

## Deliverable

Resolve Q-03 and Q-05 for R-02: a ranked, reproducible account of settling costs and specific candidate experiments.
The unknown result does not block this observational experiment.

## Experiment design

- Run one full local image suite with traces after regression checks. Keep capture geometry, flags, source revision, toolchain, host, retries, and case inventory in the evidence.
- Select two focused families from that trace, including ordinary/static sizing and native/async content. Run alternating on/off controls twice per mode, serially, using the same built products and `--record never`.
- Retrieve an isolated CI snapshot run of the instrumentation revision. Compare costs and classifications; do not combine local and CI absolute durations into one estimate.
- Bound the initial pass to one local full trace, four focused invocations, and one complete CI sample. Repeat only for a demonstrated instrumentation failure or unresolved measurement concern.
- Use selected system traces only when operation timings leave a material cause unexplained. Do not promise that elapsed sleep distinguishes app work from scheduler delay.
- Preserve raw artifacts outside Git; keep concise measurements, source/commands, and interpretation in this plan.

## Analysis and acceptance

Classify each reason/family by observed changes, time spent rendering/checking, minimum-duration gating, stability-proof gating, and repeated calls.
A phase can have multiple active gates. Do not sum overlapping conditions or call every sleep removable.
Record distributions and expensive outliers rather than only means.
Compare capture identities, dimensions, outcomes, and reference diagnostics against the current baseline.
An inconclusive overhead comparison may complete this experiment only if noise/overhead limits are explicit and no optimization relies on the uncertain estimate.
CI evidence can remain pending at an intermediate publication; do not mark this plan complete until obtained or an explicit scope revision documents its replacement.

The deliverable is a ranked candidate table with affected stages, measured cost, proposed mechanism, correctness evidence needed, and the next bounded experiment.
A negative finding is valid. Update the overview questions and refine [03](03-controlled-experiments.md) from the actual results.

## Recovery and resume point

Wait for plan 01's validated instrumentation. Retain unsuccessful runs with their errors; never substitute a favorable run without describing the failure.
No new Swift architecture is proposed: this plan consumes the trace schema and analysis tool from plan 01.
