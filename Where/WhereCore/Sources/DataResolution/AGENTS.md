# Data resolution

This directory owns detection, reviewed GPS corrections, and scan publication.
The [module rules](../../AGENTS.md) and [repository rules](../../../../AGENTS.md) also apply.
Trajectory inference has additional [flight rules](Flights/AGENTS.md).

- Apply GPS corrections only to the sample IDs the user reviewed.
  Reassess inside `perform(expectedDataGenerationID:)` and return changed evidence for a new review.
  Preserve manual assertions and conflicting duplicate samples.
  Guards: `SampleCorrectionCoordinatorTests` and `SampleCorrectionAssessmentTests`.
- Retain immutable attribution revisions, including revisions that arrive before their samples.
  Preserve bare UUID encoding and use `SampleAttributionRevision.nextUpdatedAt` for correction and reset writes.
  Clear manual overrides and write newer reset tombstones in one transaction.
  Guards: `DayJournalTests` and `LocationHistoryReaderTests`.
- Publish issues, informational reviews, and deadlines as one scan result.
  Determine correction readiness per flight, including flights on the same day.
  Keep pending-flight samples out of proposals and pending flights out of actionable counts.
  Retain pending flight information after applying or dismissing another flight's proposal on that day.
  Guards: `SampleCorrectionAssessmentTests`, `SampleCorrectionCoordinatorTests`, and `GPSCorrectionReviewTests`.
  Dismiss a ready review with its issue when no pending flight remains.
  Never let an invalidated scan restore cached data. Guard: `DataIssueScannerTests`.
- Run presentation deadlines only in the foreground. Do not add background polling.
