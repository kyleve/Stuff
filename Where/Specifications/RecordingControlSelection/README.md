# Recording control selection

Run `./tla-check RecordingControlSelection` from the repository root.

This model checks whether control delivery order or elapsed time can change precedence between a source choice, an ignore, and device removal.
It represents `RecordingControlSelection` and its tests added above `37b39f6e`.
Production history selection remains inactive.

## Source correspondence

| Model | Source boundary |
| --- | --- |
| `delivered` | Immutable controls admitted into a `RecordingControlSnapshot`, plus removal tombstones. |
| `Receive` | One atomic envelope becomes available. The reader resolves an internally consistent value snapshot. |
| `Source` | `HistoryDecisionResolver` resolves the explicit choice or its bounded return to automatic. |
| `Active`, `Heads`, `Parents` | The relevant portion of `CausalPeriodResolver`; missing predecessors remain incomplete. |
| `IgnoreAction`, `IgnoreScope` | `RecordingIgnoreDecision.action(at:)`, including a shortened ignore's eligible tail. |
| `IgnoreResult` | `RecordingIgnoreResolver` retains agreement, conflict, and missing dependencies. |
| `Removed` | The earliest device-removal cutoff used by `RecordingControlSelection`. |
| `Opaque` | An unknown control's stable affected scope. A source choice cannot resolve it. |
| `Resolve`, `views` | The selected, automatic, or unresolved result for each elementary period. |
| `clock`, `Advance` | A later query of the same historical periods. Current code does not use the wall clock to expire past ignores. |

Each delivery can repeat or arrive before its predecessor. Replicas receive independently.
Reassessment is pure and synchronous over supplied values, so delivery and the resulting view form one model step.
The model does not treat a store fetch and a later write as atomic. The reviewed-write and compatibility models own those boundaries.

## Bounds and properties

The configurations use two or three half-open time segments and one or two replicas.
There are eight immutable controls: select a source, return the last segment to automatic, ignore, resume, undo, shorten, remove, and an opaque control.
The selected device is fixed. A second device is implicitly eligible in automatic periods and cannot replace an exclusive choice.
The clock advances past the ignore's end while historical queries remain fixed.

The invariants check explicit-choice precedence, removal without fallback, historical ignores after expiry, and the distinct scopes of resume, undo, and shortening.
They also check missing dependencies, opaque scope, and equal output for equal received controls.
Negative controls filter an explicit source through an ignore, expire history by the current clock, bypass removal, or apply resume to the entire history.
Reachability cases exercise return to automatic after expiry and an explicit choice with an incompletely delivered ignore.

This safety model assumes neither delivery fairness nor eventual convergence of different input sets.
Completed states can stutter. No liveness property is claimed.
UUID uniqueness, invalid wire admission, multiple conflicting source choices, and general causal graphs are outside these bounds.
The existing decision model and Swift resolver regressions cover the latter two boundaries separately.
Raw GPS selection, geographic assessment, recording-day recovery, UI, and output publication are not yet represented here.
Slice 5 must verify those consumers before activation.

## Swift regressions

`RecordingControlSelectionTests` covers reordered controls, explicit selection with missing ignore parents, historical return to automatic, and earliest removals.
It also covers source conflicts, missing source dependencies, bounded opaque scopes, and malformed removal input.
`RecordingIgnoreResolverTests` covers expiry, resume, undo, concurrent end dates, missing parents, and exact shortened-end boundaries.
The end-date coordinator tests require another preview when a concurrent extension expands the affected tail.

## Checked result

On 2026-11-04, all eight manifest expectations passed with PlusCal 1.11 and TLA+ tools release 1.7.4 (TLC 2.19).
Java was Temurin 21.0.8+9. The tool archive SHA-256 was `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
Generated source, traces, and `summary.json` remain under `.build/tla/runs/RecordingControlSelection.fnXlyO/`.

| Configuration | Result | Generated / distinct states | Depth |
| --- | --- | ---: | ---: |
| `Current.cfg`: two periods, one replica | Pass | 6,913 / 768 | 11 |
| `CurrentTwoReplicas.cfg`: three periods, two replicas | Pass | 4,456,449 / 262,144 | 20 |
| `IgnoreExplicit.cfg` | Expected precedence failure | 23 / 21 | 3 |
| `ExpireByNow.cfg` | Expected historical-ignore failure | 428 / 143 | 5 |
| `IgnoreRemoval.cfg` | Expected removal failure | 27 / 25 | 3 |
| `GlobalResume.cfg` | Expected scope failure | 42 / 33 | 3 |
| `LateControlReachability.cfg` | Historical return to automatic reached | 2,723 / 513 | 7 |
| `PartialDeliveryReachability.cfg` | Explicit choice with missing ignore parent reached | 26 / 24 | 3 |

The inspected negative traces have these source-level interpretations:

- An ignore arrives after a source choice. Filtering the explicit choice through that ignore wrongly excludes its device.
- An ignore arrives after its end date. Comparing with the wall clock wrongly makes its historical interval eligible.
- Removal arrives after a source choice. Bypassing the cutoff wrongly leaves its later portion selected without review.
- Resume arrives after an ignore. Applying it globally wrongly restores the elapsed interval.

**Verified for these model bounds and assumptions.** The result does not prove the Swift implementation or the remaining shared-history consumers.
