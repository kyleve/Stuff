# Test simplification

## Planning checkpoint

- Updated: 2026-11-15, baseline `2193072f6a1c988f797c77c14c3b6cf0923d8ca0`.
- Operation: approved implementation delivered; integrate current `main` at Kyle's request.
- Authorization: Kyle requested both snapshot phases, guidance improvements, and other supported audit improvements on 2026-11-15.
- Stage: implementation complete; PR review.
- Completed: audit, all three deliverables, remaining candidate assessment, focused checks, and independent reviews.
  [01](01-unit-tests-and-guidance.md) is in `7c3a06da1`; [02](02-snapshot-phase-one.md) is in `d36763ed8`; [03](03-snapshot-phase-two.md) is the final implementation commit.
- Main integration: `15195ab9c8abfbf61f5619ecdd6e680887487211`; guidance conflicts reconciled and focused merge checks passed. See the integration record below.
- Pending: PR review and CI on the final published revision. No implementation step remains.
- Next action: review [PR #505](https://github.com/kyleve/Stuff/pull/505).
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
- Implementation and focused runtime results are recorded in the numbered plans. Rendered Xcode previews remain unverified.

## Delivered result

These counts describe the original audit baseline through `6f2bc86e9`.

| Inventory | Before | After | Removed |
| --- | --- | --- | --- |
| Unit-test declarations | 3,030 | 2,973 | 57 |
| Snapshot reference PNGs | 954 | 889 | 65 |
| Reference panels | 1,011 | 946 | 65 |

The removed PNGs represent 97.2 MiB of hydrated reference data. All retained PNG bytes are unchanged.
Focused unit runs passed 72, 15, and 23 tests; these selections overlap.
Strict image runs covered 219 distinct retained references, with all 61 MainTabs images repeated after the preview correction.
The Locations loading/failed navigation-bar and inset probes also passed.
Formatting, guidance synchronization, skill validation, shard inventory, and the wrapper's architecture/host checks passed.

Coverage now follows distinct behavior and visual risk. The selected tablet matrices retain five phone traits and a light tablet baseline.
The FlightReviewPointRow fixture keeps its Form context and tablet baseline; its parent's collapsed disclosure does not replace that coverage.
Stylesheet calculations, accessibility constraints, environment propagation, fold behavior, and device stack guards remain.
Independent reviews found two preview issues, both corrected before publication, and no remaining actionable code finding.
This is a maintenance reduction, with no measured runtime claim.

## Main integration — 2026-11-15

Kyle requested a merge after the guidance simplification in [#507](https://github.com/kyleve/Stuff/pull/507).
Merged `15195ab9c8abfbf61f5619ecdd6e680887487211` into the existing feature branch.
Kept main's shorter skill entry points, conditional references, Periscope contracts, and removal of the `simple-english` external skill.
The obsolete local installation was moved outside the checkout; `./sync-agents` removed its recognized Claude link.

The two text conflicts were in `running-tests/SKILL.md` and `PeriscopeTools/AGENTS.md`.
The former retains focused suite selection and moves snapshot-selection policy into main's new `running-tests/references/snapshots.md`.
The latter uses main's concise module contract, which also removes the obsolete test-file prescription.
The root testing-policy route and other coverage-policy changes remain.

Reviewed the integration against `6f2bc86e9` and the merged main revision.
Every Swift and PNG diff entry against the new base matches the previously reviewed implementation diff exactly.
Main adds two Device Layout Lab unit tests and four references through [#504](https://github.com/kyleve/Stuff/pull/504).
Against the new base, this branch still removes 57 unit-test declarations (3,032 to 2,975) and 65 references (958 to 893).

Merge validation passed on Xcode 27.2 / iOS 27.2:

```sh
./test --record never --timings \
  --only WhereUITests/DeviceLayoutLabViewTests \
  --only WhereUISnapshotTests/DeviceLayoutLabViewSnapshotTests
```

The run passed three unit tests and two snapshot tests with nine comparisons against eight references.
The light phone capture recovered on its built-in second settling attempt. No references were recorded.
The wrapper's architecture, Flyover, attribution, and backup-upgrader checks also passed.
Guidance synchronization, all eight changed owned-skill entry-point validations, SwiftFormat for the two incoming Swift files, and diff checks passed.
The guidance inventory has 57 instruction files and 13 owned skills; the largest chain is 23,734 of 28,672 bytes.
The root contract is 5,611 bytes; the `running-tests` entry point is 3,388 bytes.
The prior focused test evidence remains recorded above; the full local suite and rendered Xcode previews were not rerun for this merge.

## Related work and delivery

- [STU-20](https://linear.app/kve/issue/STU-20) remains open: removing a quarantine does not prove a renderer fix.
- [STU-246](https://linear.app/kve/issue/STU-246) owns the separate Manual Day range-mode gap; existing named states remain.
- [STU-49](https://linear.app/kve/issue/STU-49) owns the remaining Periscope mount-only checks; this series removes the two viewer checks and replaces its blanket snapshot prescription with the current selection policy.
- Implementation PR: [#505](https://github.com/kyleve/Stuff/pull/505).
- Outcome: implemented, verified, and published for review.
