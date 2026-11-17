# Reusable snapshot data

## Planning checkpoint

- Updated: 2026-11-17; parent PR #515 at `d3f012395d1632fc6b2f0ead9977bcaf544b1bdb` after #511 and #512 merged.
- Operation: Execute the user's request to try fixed report reuse and demo seed reuse.
- Stage: Complete; [PR #516](https://github.com/kyleve/Stuff/pull/516) is ready for review.
- Completed: Both bounded experiments, retained report reuse, focused unit/image checks, broad WhereUI images, independent review, and publication. Parent rebases preserve the earlier `2736e1a7f` source tree. An earlier parent web job stopped with a runner shutdown and was retried.
- Pending: Remote CI results on the final published tip. PR #516 owns the manual GitHub/CircleCI dispatch records. Broader write/reconciliation work remains in STU-121.
- Next action: Review PR #516 and its CI results. No further local implementation is required for these experiments.

## Outcome and requirements

US-01: As a maintainer, I want faster snapshot setup while each test keeps its own mutable world.

| ID | Requirement | Plan |
| --- | --- | --- |
| R-01 | Reuse immutable fixed report/day/location values without changing date or calendar behavior. | 01 |
| R-02 | Try reuse of immutable demo inputs while keeping fresh stores, services, sessions, preferences, and publication models. Preserve per-world record identity and ordinary write paths. | 02 |
| R-03 | Measure generation separately from insertion/reconciliation. Retain simple, supported improvements and record negative results honestly. | 01–02 |
| R-04 | Preserve capture identity, content, references, tolerances, and readiness policies. Remove temporary probes before publication. | 01–02 |
| R-05 | Review and publish verified steps above PR #515; keep the broader profiling issue open. | 01–02 |

X-01: No shared mutable worlds, stores, model containers, or preferences; no production cache singleton or generic static registry.
X-02: No direct seed writes that bypass the ordinary journal/reconciliation path, lighter demo scenarios, or changed snapshot matrices.

## Context and evidence

This follows [shared artwork](../2026-11-17-snapshot-artwork/README.md) and [STU-121](https://linear.app/kve/issue/STU-121). The user approved both candidates on 2026-11-17. The earlier 24.776s for 39 demo scopes includes database and service work; it is not an estimate of cacheable time.

`PreviewSupport.sampleReport()` rebuilds a fixed 285-day report. `sampleYearReportDetails()` adds fixed point clouds and a new resolver input. The report and points are value types. The resolver input constructs a calendar for the current time zone, which must not accidentally freeze at first access.

`DemoDataBuilder.seed(into:)` generates samples/backfills/corrections, then uses normal service writes. Samples receive new UUIDs and are stamped with the destination recording device. `WhereScope.demo` also creates a store, services, and log store. Preparation costs must distinguish those phases.

Repository source and prior local profiles establish the design; no new external API is needed. Tests use Xcode 27.2 and the repository's `./test` runner.

## Execution and questions

1. [01 — Fixed report values](01-fixed-report-values.md).
2. [02 — Demo seed inputs](02-demo-seed-inputs.md).

| ID | Status | Question | Resolution |
| --- | --- | --- | --- |
| Q-01 | closed | What can be shared without freezing mutable state or time-zone behavior? | Cache fixed report/day/point values at PreviewSupport. Keep the resolver wrapper and all models/services fresh. Demo candidates must preserve configuration, reference time, calendar, and fresh sample identity. |
| Q-02 | closed | How much setup time can report reuse remove? | Three batches of 500 report and 500 detail calls take 0.872482s before and 0.004922s after, including first use. This proves avoided factory work; the original per-call cost is only about 0.29ms. No suite-wide saving is established. |
| Q-03 | closed | Is demo recipe generation large enough to justify an explicit prepared-value seam? | Two processes with five fresh worlds each measure only 0.44–0.47ms median generation, versus 0.92–0.94s per world. Even eliminating generation saves about 0.02s over 39 worlds. No prepared-input API is justified; plan 02 records the supported negative result. |

## Plan review

Reviewed 2026-11-17 against `bc02a4595`: value ownership, time-zone capture, sample identity, write fan-out, isolation, and existing guards. Both bounded plans are ready. The original full image profile at `2736e1a7f` is source-equivalent after rebase; timings from that run remain a single earlier sample. The numbered plans contain design sketches, not runtime evidence.

## Review and delivery

Branch: `perf/snapshot-fixture-data`, [PR #516](https://github.com/kyleve/Stuff/pull/516), above #515 in stack #513. Report implementation: `50a138520`; negative experiment record: `9005c92f0`. The complete tree before and after the final rebase is `f6f5b30a643ad4619ee1489c550dbf3d691bbd31`, so local evidence applies to the published implementation. Later edits only complete documentation.

Independent review found no actionable source or evidence issues. It verified the raw measurements, all 33 unit tests, focused diagnostics, 801-capture inventory, and rebase equivalence. Full image assertions establish reference acceptance, not pixel-exact equality. Manual GitHub/CircleCI gates target the final publication tip; their links and remote status live in PR #516. The unrelated untracked simple-english skill was restored byte-for-byte after synchronization and is outside this work.

## Outcome

Report factories now reuse immutable values; their current-calendar wrappers and mutable dependencies retain existing ownership. Demo input caching has a supported negative result and adds no API. These experiments are delivered in PR #516. [STU-121](https://linear.app/kve/issue/STU-121) remains In Review for unmerged work and broader profiling opportunities.
