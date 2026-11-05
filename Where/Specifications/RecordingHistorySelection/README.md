# Recording history selection

Run `./tla-check RecordingHistorySelection` from the repository root.

This bounded model checks retained evidence, source selection, logical dates, report completeness, and export snapshots.
It follows the [recording contract](../../MULTI_DEVICE_RECORDING.md#formal-verification) and the [specification workflow](../README.md).
Production remains on the foundation contract until the activation gates pass.

## Source correspondence

| Model boundary | Implementation |
| --- | --- |
| `received`, immutable observation fields | `RecordingHistorySelection.Evidence.observations` retains admitted measurements and effective recording-day assignments. |
| Observation or control delivery in `Act` | A new internally consistent value snapshot reaches `LocationHistoryReader`. Import and sync use the same selection path. |
| `Choices`, `AppliedChoices` | `HistoryDecision.periods` and `RecordingControlSelection` apply a source choice only within its stored periods. |
| `AutomaticEvidence`, `RelevantEvidence` | A resolved historical ignore filters automatic evidence by observation time. Explicit source selection bypasses that ignore. |
| `Segment`, `Selected` | `RecordingHistorySelection.Builder` composes explicit choices with `MultiDeviceAssessment` results. |
| `Day`, `Geography`, `Resolve` | Recording assignments and specific geography precede aggregation and reporting groups. Viewer zones do not change those assignments. |
| Candidate dates and `unassigned` | `RecordingHistorySelection.Issue.days` and `HistoryCompleteness` retain unresolved scope separately from eligible contributions. |
| Full version and query in `views` | `RecordingEvidencePolicy.version`, `LocationHistoryQuery`, and `HistoryCompleteness` identify an assessment. `WidgetSnapshotStore` rejects stale full-policy output. |
| Export preparation | `ReportReader.exportableYearReport` checks completeness on the returned immutable report. |
| Export publication | A later document consumer uses that checked value. It must not fetch different content after checking eligibility. |

Delivery and reassessment form one labeled step because selection is synchronous over supplied values.
This step does not assert atomicity across independent store reads.
Production assembles those values within `WhereStore.readSnapshot`; store tests cover that boundary.
Export preparation and publication are separate transitions, so evidence can arrive between them.
The production export API returns assessed data; this slice does not add a document format or export screen.

## Bounds and assumptions

The configurations use one or two replicas, two devices, and one to three elementary absolute-time periods.
Each device supplies at most one immutable evidence item per period.
An item represents a supported track and its candidate contribution, rather than one isolated GPS point.
The regions scenario assumes repeated, accurately separated positions establish divergence.
The days scenario assumes ambiguous movement when simultaneous tracks have different date labels.
The unknown scenario includes unresolved geography and, separately, an unresolved day assignment.
Neither track has a strong movement preference in that scenario.
Numeric zero denotes unknown context only; it is never a real date or region.

In the days scenario, the whole-day choice selects device A in periods 0 and 2.
Period 1 carries another date and stays outside that choice.
A concurrent fixed-period choice selects B in the last period.
Their overlap requires review without changing earlier or intervening periods.
Stored calendar coverage establishes these periods before selection; GPS gaps do not establish or invalidate that coverage.
The model preserves this bounded result and does not calculate real time-zone transitions.
Other scenarios reuse A's stored periods as a fixed-range source choice, with different evidence labels.
They supply no whole-day metadata. The `dayA` operation name remains the same across configurations.

One configuration adds a historical ignore of A in period 0.
Later observations from A remain raw but cannot contribute automatically during that period.
Explicit choices still include A, and observations after the ignore remain automatically eligible.
Delivery order can place the ignore before or after its observations.

Replicas receive evidence and controls independently, including duplicate deliveries.
Queries include either date or both dates. Two viewer zones can alternate.
Receipt of a fixed evidence identity always means the same payload.
Identity collisions, wire admission, corrections, and calendar recovery are tested separately in Swift.

Policies 1 and 2 represent two compatible full versions with identical explicit-choice semantics.
The second policy selects A automatically for one borderline movement scenario that the first policy leaves unresolved.
This is a hypothetical compatibility case. Swift currently implements only `RecordingEvidencePolicy.version` and rejects other selection versions.
The model does not assert that Swift executes two assessment algorithms.

Ignore resolution, resume, undo, expiry, removal, opaque controls, and missing dependencies belong to [RecordingControlSelection](../RecordingControlSelection/README.md).
This model tests integration with a resolved ignore interval, without duplicating its causal state machine.
Causal decision convergence belongs to [MultiDeviceDecisions](../MultiDeviceDecisions/README.md).
Reviewed saves and compatibility permits have separate models and transaction regressions.
These models check different boundaries; their separate passing results do not prove an automatic composition theorem.

All configurations check safety. No delivery fairness or eventual completion is assumed.
Duplicate delivery permits stuttering after the bounded operations finish.
The model does not prove GPS thresholds, platform restore behavior, CloudKit atomicity, UI routing, or notification delivery.

## Properties and counterexamples

The passing cases check equal output for equal evidence, controls, full versions, and queries.
They also check raw retention, exclusive gaps, logical-date stability, bounded whole-day overlap, candidate completeness, and independent resolved presence.
Every supported policy must retain the selected device's available evidence within an explicit choice.
Geographic uncertainty establishes neither agreement nor a source conflict.
Without independent movement evidence, unknown calendar context cannot silently promote a rival device.
Exports must use the checked snapshot and contain no unresolved history within their scope.

Each deliberately broken implementation must fail its named invariant:

| Variant | Counterexample |
| --- | --- |
| `prune-raw` | A conflicting track causes the derived selection to discard received raw evidence. |
| `fill-gap` | A supplies an observation before selected device B uploads. A incorrectly fills B's exclusive gap. |
| `viewer-day` | Changing the viewer zone changes a retained contribution's logical date. |
| `major-cache` | A compatible policy change reuses output from the previous full version. |
| `query-cache` | A new logical-date query reuses the previous query's assessed output. |
| `group-other` | Grouping distinct regions before assessment turns divergent tracks into agreement. |
| `continuous-day` | Taking the hull of repeated-day periods suppresses B's valid intervening-date contribution. |
| `drop-candidate` | An unresolved overlap loses a candidate date needed for incomplete reporting. |
| `split-export` | A complete snapshot passes eligibility; a later conflicting snapshot supplies the exported content. |
| `drop-issue` | An all-days query omits a geographic conflict from completeness. |
| `ignore-explicit` | Applying an ignore before the explicit choice drops the selected device's available observation. |
| `policy-choice` | A compatible policy retains the explicit choice but drops all its available observations. |

Reachability controls exercise a late selected-device upload after a gap, compatible automatic differences, and a conflict after export preparation.
A fourth control reaches unresolved and independently resolved presence on the same logical date.
A fifth reaches an ignored observation that arrives after its ignore interval was received.

Independent review found two missing positive guards in the initial model.
Excluding disputed contributions did not require the conflict to remain in completeness.
Excluding other devices did not require the selected device's observations to survive a compatible policy change.
The final model checks both requirements directly and includes negative controls for their violations.
The export configuration also includes an independent valid period beside a conflict.

## Swift regressions

- `RecordingHistorySelectionTests` covers exclusive gaps, raw retention, duplicate/reordered evidence, unknown geography, conflicting days, and independent contributions.
  Its repeated-day regression also exercises the selector with a concurrent fixed-period choice.
  Its late-ignore regression covers historical filtering, explicit selection, and return to automatic after the ignore's end.
- `RecordingChoiceCoordinatorTests.repeatedLogicalDayChoicesRetainTheInterveningGap` checks the stored noncontiguous periods derived from calendar context.
  `RecordingDayCoverageTests` checks actual day boundaries and offset changes.
- `ReportReaderTests.checkedExportSnapshotSurvivesAConflictReceivedBeforeDocumentGeneration` retains checked content across a later import.
  Its conflict and regrouping regressions verify incomplete exports, scoped eligibility, late selected evidence, and unchanged raw storage.
- `HistoryCompletenessTests` checks candidate dates, unknown assignments, full policy identity, and rejected unassessed scope expansion.
- `LocationHistoryReaderTests` and `LocationHistoryQueryTests` cover selected logical dates, viewing zones, UTC-year boundaries, and offset-complete queries.
- `WidgetSnapshotStoreTests.stalePolicyCannotPresentOldCounts` rejects stale minor, patch, and major output versions.
  Swift tests do not establish the hypothetical second policy's automatic algorithm.

## Checked result

On 2026-11-05, all 22 manifest expectations passed with PlusCal 1.11 and TLA+ tools release 1.7.4 (TLC 2.19).
Java was Temurin 21.0.8+9. The archive SHA-256 was `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
Generated source, traces, and `summary.json` remain under `.build/tla/runs/RecordingHistorySelection.tWrqO3/`.
The runner verified that translation did not change the tracked PlusCal source.

| Configuration | Result | Generated / distinct states | Depth |
| --- | --- | ---: | ---: |
| `CurrentReplicas.cfg` | Pass | 1,039,681 / 51,984 | 15 |
| `CurrentLogicalDays.cfg` | Pass | 51,073 / 3,648 | 12 |
| `CurrentUnknown.cfg` | Pass | 10,945 / 912 | 10 |
| `CurrentExport.cfg` | Pass | 7,911 / 1,214 | 9 |
| `CurrentHistoricalIgnore.cfg` | Pass | 141,121 / 9,408 | 13 |
| `PruneRaw.cfg` | Expected failure | 7 / 6 | 3 |
| `FillGap.cfg` | Expected failure | 9 / 8 | 3 |
| `ViewerDay.cfg` | Expected failure | 21 / 16 | 3 |
| `MajorCache.cfg` | Expected failure | 7 / 6 | 2 |
| `QueryCache.cfg` | Expected failure | 8 / 7 | 2 |
| `GroupOther.cfg` | Expected failure | 7 / 6 | 3 |
| `ContinuousDay.cfg` | Expected failure | 48 / 33 | 3 |
| `DropCandidate.cfg` | Expected failure | 7 / 6 | 3 |
| `SplitExport.cfg` | Expected failure | 83 / 38 | 5 |
| `DropIssue.cfg` | Expected failure | 10 / 9 | 3 |
| `IgnoreExplicit.cfg` | Expected failure | 41 / 22 | 4 |
| `PolicyChoice.cfg` | Expected failure | 107 / 44 | 4 |
| `LateSelectedObservation.cfg` | Reached | 34 / 15 | 4 |
| `CompatibleAutomaticDifference.cfg` | Reached | 13,993 / 2,527 | 6 |
| `CompleteExportThenConflict.cfg` | Reached | 38 / 18 | 4 |
| `PartialDay.cfg` | Reached | 670 / 174 | 5 |
| `LateIgnoredObservation.cfg` | Reached | 62 / 29 | 4 |

These results apply only to the stated bounds and assumptions.
Relevant implementation changes require a new correspondence review and model run before activation.
