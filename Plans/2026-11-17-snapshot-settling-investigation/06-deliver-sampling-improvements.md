# 06 — Deliver accepted sampling improvements

- Status: outline
- Depends on: [05](05-metal-and-sampling-experiments.md).
- Shared context: [Overview](README.md), R-06, X-02–X-04, Q-06–Q-08.

## Intended outcome

Ship only a candidate supported by plan 05, or document the bounded negative result and restore the unchanged renderer. Explicit fallback for incompatible tests is authorized by the user. A general Metal default is provisional, not required.

## Requirements and exclusions

Preserve coverage, references, final capture rendering, geometry, readiness hooks, quiet proof, minimum durations, cancellation, timeout/starvation behavior, retries, and cleanup. Keep resource ownership bounded; avoid hidden per-class readiness inference. Remove experiment flags and dump code. The existing pipeline in plan 05 remains the architectural boundary; accepted results determine whether any new maintained component is needed.

## Refinement trigger and evidence

Refine after plan 05 establishes fidelity, local timing, and any explicit fallback eligibility. Select meaningful retained regressions for demonstrated failures. A renderer-wide accepted change requires framework and complete 935-capture local validation, actual isolated-CI capability evidence, and matched CI timing before claiming a CI gain. Keep repeated focused savings separate from full-run observations.

Review the final diff with a fresh independent reviewer, publish a ready PR above #525, and update STU-121 without closing its unrelated remaining work. A negative experiment can finish this delivery through documented findings and any useful regression coverage; it does not establish feasibility or a speedup.
