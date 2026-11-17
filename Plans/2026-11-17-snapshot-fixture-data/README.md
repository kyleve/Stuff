# Reusable snapshot data

## Planning checkpoint

- Updated: 2026-11-17; parent PR #515 at `bc02a45954a642dfdd90f4701432eb23d648cdb4` after stack synchronization.
- Operation: Execute the user's request to try fixed report reuse and demo seed reuse.
- Stage: Ready for baseline profiling.
- Completed: Source and contract inspection; synchronized the stack after #511 merged. The source tree matches the earlier `2736e1a7f` baseline. The parent web job stopped with a runner shutdown, not a test assertion; it was retried.
- Pending: Separate measurements, bounded candidates, validation, independent review, and publication.
- Next action: Measure fixed report construction and five fresh demo worlds with temporary subphase instrumentation.

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
| Q-02 | open | How much setup time can report reuse remove? | Measure repeated factory calls and representative snapshot consumers. |
| Q-03 | open | Is demo recipe generation large enough to justify an explicit prepared-value seam? | Split five fresh worlds into store/services/generation/writes/log/report phases; run at most one prepared-input candidate. A supported negative result satisfies this bounded experiment. |

## Plan review

Reviewed 2026-11-17 against `bc02a4595`: value ownership, time-zone capture, sample identity, write fan-out, isolation, and existing guards. Both bounded plans are ready. The original full image profile at `2736e1a7f` is source-equivalent after rebase; timings from that run remain a single earlier sample. Mermaid below is a source sketch, not runtime evidence.

## Review and delivery

Branch: `perf/snapshot-fixture-data`, above #515 in stack #513. Use independent completed-diff review and final manual GitHub/CircleCI gates. The unrelated untracked simple-english skill was restored byte-for-byte after stack synchronization and is outside this work.

## Outcome

In progress. Preserve experiment results and remaining work in STU-121.
