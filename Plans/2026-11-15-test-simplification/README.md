# Test simplification

## Planning checkpoint

- Updated: 2026-11-15, baseline `2193072f6a1c988f797c77c14c3b6cf0923d8ca0`.
- Operation: execute the approved audit recommendations.
- Authorization: Kyle requested both snapshot phases, guidance improvements, and other supported audit improvements on 2026-11-15.
- Stage: implementation.
- Completed: source, reference, guidance, and relevant fix-history audit; plan review; clean baseline check.
- Pending: the three numbered deliverables, focused verification, independent review, and publication.
- Next action: implement [01](01-unit-tests-and-guidance.md).
- Branch: `codex/test-maintenance-reduction`.
- Tracking: [STU-332](https://linear.app/kve/issue/STU-332/reduce-low-value-tests-and-automatic-snapshot-matrix-growth).

## Outcome and requirements

US-01: As a maintainer, I want fewer redundant tests so behavior changes and visual edits require less maintenance.

| ID | Requirement | Plan |
| --- | --- | --- |
| R-01 | Remove copied defaults and weak assertions; retain behavioral and regression guards. | [01](01-unit-tests-and-guidance.md) |
| R-02 | Stop guidance from requiring a test per file, token, or preview state. | [01](01-unit-tests-and-guidance.md) |
| R-03 | Apply the first 29-reference snapshot reduction with explicit retained identities. | [02](02-snapshot-phase-one.md) |
| R-04 | Apply the second 32-reference reduction and assess the other audit candidates. | [03](03-snapshot-phase-two.md) |
| R-05 | Preserve application behavior, useful preview states, capture fidelity, and meaningful failure guards. | All |

X-01: No production behavior, comparison tolerance, external skill, or toolchain changes.
X-02: No arbitrary test-count target, blanket accessibility removal, or replacement tests that copy implementation.

## Evidence and decisions

The baseline contains 3,030 unit-test declarations, 76 snapshot-test declarations, and 954 reference PNGs.
The PNGs represent 1,011 panels because 57 files contain two-panel comparisons.
These counts exclude parameter expansion and additional render probes.

The accepted audit identifies 50 unit-test removals, including 28 stylesheet tests with 277 copied-value assertions.
It also identifies mixed stylesheet tests whose semantic assertions remain useful.
The snapshot passes remove 29 and 32 references, respectively, before any separately reviewed fixture change.

Retain the 16 KiB view-body guards: fixes #327 and #409 demonstrated device stack failures before those boundaries.
Retain cancellation, fold-state preservation, persisted identities, backup integrity, privacy filtering, and renderer correctness checks.
Calendar, Timeline, flight-detail, and gallery matrices already received substantial reductions in #436 and #438.

Repository source and history establish these decisions; no external research is required.
No data flow or Swift architecture changes are proposed, so a diagram and architecture sketch do not apply.

## Contract map

| Owner | Preserved contract and guards |
| --- | --- |
| `.agents/references/swift-conventions.md` | Behavioral test selection; observable conditions and isolated fixtures |
| `Shared/SnapshotKit/AGENTS.md` | Explicit configurations, stable identities, production frames, independent fixtures |
| `Shared/SnapshotKitTesting/AGENTS.md` | Readiness, strict comparison, panel budgets, and serial rendering |
| `Where/WhereUI/Tests/AGENTS.md` | Root propagation, full-content coverage, theme ownership, and Flyover states |
| `Where/WhereUI/Sources/Primary/AGENTS.md` | Fold state, native pane ownership, load-state insets, and view-body budgets |
| `Where/WhereUI/Sources/Year/AGENTS.md` | Calendar/Timeline ownership and one navigation stack with a retained selector |
| `Shared/InstallerKitUI/AGENTS.md` | Failure descriptions, cached-data visibility, and public-root propagation |
| `.agents/AGENTS.md` | One rule owner, loading routes, external pins, and guidance budgets |

## Execution order and horizon

1. [Unit tests and guidance](01-unit-tests-and-guidance.md): remove weak assertions and correct coverage policy.
2. [Snapshot phase one](02-snapshot-phase-one.md): narrow repeated wrapper and load-state captures.
3. [Snapshot phase two](03-snapshot-phase-two.md): narrow repeated tablet traits and assess remaining candidates.

All three plans have executable detail from the accepted audit. Each deliverable receives its own commit and verification evidence.

## Questions and resolutions

- Q-01, closed: maintenance burden takes priority over a runtime target. Source: audit discussion and approval.
- Q-02, closed: representative coverage replaces exhaustive repeated matrices. Source: audit discussion and approval.
- Q-03, closed: implementation is authorized. Source: the 2026-11-15 request to proceed with both phases and guidance improvements.

## Plan review

- Reviewed on 2026-11-15 against the baseline, selected sources, guidance owners, reference identities, and prior fixes.
- All requirements map to a deliverable. No unresolved product decision blocks execution.
- The retained-identity audit and focused assertion runs distinguish a coverage reduction from an accidental image update.
- Implementation and runtime results remain unverified until recorded in the numbered plans.

## Related work and delivery

- [STU-20](https://linear.app/kve/issue/STU-20) remains open: removing a quarantine does not prove a renderer fix.
- [STU-246](https://linear.app/kve/issue/STU-246) owns the separate Manual Day range-mode gap; existing named states remain.
- Implementation PR: pending.
- Outcome: in progress.
