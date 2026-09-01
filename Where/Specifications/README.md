# Formal protocol specifications

These bounded models check narrow concurrency and lifecycle claims in Where.
The editable algorithm source is C-syntax PlusCal embedded in each concern's
`.tla` module; invariants and temporal properties remain TLA+. Generated TLA+
is build output and is never committed.

## Authoring and running

Each concern contains one model module, its TLC configurations, a
`manifest.json`, and a README mapping model state and actions to production
code. The manifest declares `source` as `pluscal` or `tla`; use raw TLA+ only
when a declarative/refinement model or source-faithful fairness cannot be
expressed cleanly in PlusCal, and document that decision in the concern README.

For PlusCal models:

- put an explicit label at every modeled atomicity boundary;
- keep one source action in one labelled step;
- use `||` when assignments must read the same pre-state;
- express action-level fairness with `fair process`, not global algorithm
  fairness;
- never run `pcal.trans` against the tracked file.

Run a selected concern or all repository concerns from the repository root:

```sh
./tla-check TrackingReconciliation
./tla-check
```

Concern folder names must be unique across the top-level feature directories.
The command uses the folder name as its compatible selection key.

The checker copies the concern into an isolated
`.build/tla/runs/<Concern>.<run>/generated/` directory, translates the copy with
the pinned PlusCal translator, and runs every manifest case against that
generated module. The run directory retains the module, TLC logs and state, and
`summary.json`. The checker verifies that the tracked source's SHA-256 is
unchanged before returning.

## PlusCal migration result

The nine raw-TLA models at commit `2a6c695bdb8d` on 2026-08-13 were checked
before conversion, then all 25 cases were repeated through generated PlusCal
1.11 output with TLC 1.7.4 and Eclipse Temurin 21.0.8. The case matrix reports
generated states / distinct states / graph depth; “same” means the generated
PlusCal result is identical to the raw-TLA result.

| Concern / case | Verdict, raw → generated PlusCal | States, raw → generated PlusCal |
| --- | --- | ---: |
| IngestorQuiesce / `broken` | fail `NoPersistAfterQuiesceDone` → same | 22 / 19 / 6 → same |
| IngestorQuiesce / `current` | pass → pass | 36 / 26 / 10 → same |
| IntentServicesHandoff / `broken` | fail `NoSelfCreate` → same | 2 / 2 / 2 → same |
| IntentServicesHandoff / `current` | pass → pass | 19 / 9 / 5 → same |
| LaunchLifecycle / `broken` | fail `MemoNoDoubleRun` → same | 6 / 6 / 4 → same |
| LaunchLifecycle / `current` | pass → pass | 27 / 15 / 7 → same |
| LogRouting / `broken` | fail `ShadowedScopeNeverRoutes` → same | 4 / 4 / 2 → same |
| LogRouting / `current` | pass → pass | 54 / 14 / 4 → same |
| PostWriteReconcile / `broken` | fail `BrokenNoEarlyPing` → same | 5 / 5 / 4 → same |
| PostWriteReconcile / `current` | pass → pass | 17 / 8 / 8 → same |
| RemoteDeviceRemoval / `broken` | fail `RemovalDominatesAdvisoryState` → same | 232 / 109 / 5 → 243 / 118 / 5 |
| RemoteDeviceRemoval / `critical-reachability` | fail `CriticalScenarioNotReached` → same | 15,393 / 3,577 / 13 → 16,753 / 3,858 / 13 |
| RemoteDeviceRemoval / `reordered-cutoff-reachability` | fail `EarlierCutoffNeverArrivesLate` → same | 625 / 282 / 5 → 506 / 235 / 5 |
| RemoteDeviceRemoval / `current` | pass → pass | 22,631 / 4,888 / 19 → same |
| RemoteDeviceRemoval / `current-multiple` | pass → pass | 678,105 / 113,648 / 23 → same |
| ScopeExclusivity / `broken` | fail `NoOverlappingRealContainers` → same | 12 / 7 / 4 → same |
| ScopeExclusivity / `current` | pass → pass | 40 / 11 / 7 → same |
| StorePerformSerialization / `broken` | fail `AtMostOneOutermost` → same | 4 / 4 / 3 → same |
| StorePerformSerialization / `current` | pass → pass | 20 / 13 / 5 → same |
| TrackingReconciliation / `broken` | fail `CorrectAtQuiescence` → same | 33 / 26 / 8 → 35 / 26 / 8 |
| TrackingReconciliation / `stale-reachability` | fail `StalePermissionNotObserved` → same | 5 / 5 / 4 → 6 / 6 / 4 |
| TrackingReconciliation / `current` | pass → pass | 22 / 16 / 8 → same |
| TrackingReconciliation / `current-denied` | pass → pass | 22 / 16 / 8 → same |
| TrackingReconciliation / `current-repeated` | pass → pass | 96 / 56 / 12 → same |
| TrackingReconciliation / `current-reversed` | pass → pass | 17 / 12 / 8 → same |

Every passing configuration retained the exact generated-state count,
distinct-state count, and graph depth. All 12 negative and reachability
controls still fail the same named properties with the same domain-state
counterexample conditions. The checked liveness, deadlock, and reachability
outcomes are unchanged. Some early-exit controls enumerate independent enabled
actions in a different order, which changes their partial state counts shown
above but not their counterexample depth or verdict.

| Concern | Authored lines, raw → PlusCal |
| --- | ---: |
| IngestorQuiesce | 113 → 94 |
| IntentServicesHandoff | 123 → 116 |
| LaunchLifecycle | 141 → 113 |
| LogRouting | 136 → 121 |
| PostWriteReconcile | 114 → 107 |
| RemoteDeviceRemoval | 286 → 245 |
| ScopeExclusivity | 108 → 93 |
| StorePerformSerialization | 128 → 119 |
| TrackingReconciliation | 212 → 193 |

The source-only models total 1,201 lines, down from 1,361 raw-TLA lines
(11.8%), and replace every primed assignment and `UNCHANGED` clause with 67
labelled process actions. PlusCal 1.11 elides `pc` entirely for these
single-label process loops, so no generated control variable enters `TypeOK`
or the state vector; adding a second control label would invalidate that
assumption and require explicit `pc` validation.

Three warm model-checking samples showed no material runtime regression:

| Configuration | Raw-TLA median | Generated-PlusCal median | Change |
| --- | ---: | ---: | ---: |
| `TrackingReconciliation/CurrentRepeated.cfg` | 0.765 s | 0.779 s | +1.8% |
| `RemoteDeviceRemoval/CurrentMultiple.cfg` | 9.948 s | 9.681 s | −2.7% |

These results are evidence only for the bounds and assumptions in each
concern's README. Relevant implementation or translator changes invalidate the
result until the source correspondence and model are checked again.
