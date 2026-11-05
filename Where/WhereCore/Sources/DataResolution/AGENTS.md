# Data resolution

This directory owns detection, reviewed GPS corrections, and scan publication.
The [module rules](../../AGENTS.md) and [repository rules](../../../../AGENTS.md) also apply.
Trajectory inference has additional [flight rules](Flights/AGENTS.md).

- Apply GPS corrections only to the sample IDs the user reviewed.
  Reassess inside `perform(expectedDataGenerationID:)` and return changed evidence for a new review.
  Preserve manual assertions and conflicting duplicate samples.
  Guards: `SampleCorrectionCoordinatorTests` and `SampleCorrectionAssessmentTests`.
- Keep selection exclusions in boundary corroboration and relevant selection metadata in review equality.
  Preserve selected logical days through review and Apply. Restore specific GPS geography before applying reporting groups to previews.
  Read current primary regions in the same snapshot. Reassess proposed geography with all competing observations before showing the resulting regions.
  Derive individual recording point previews on demand from their immutable evidence. Keep guarded Apply validation independent of whether a preview was requested.
  Guards: `SampleCorrectionAssessmentTests` and `SampleCorrectionCoordinatorTests`.
- Offer explicit point corrections only within completed flights on the same recording device.
  Recheck the full review before inclusion or restoration. Write a newer reset revision to restore GPS attribution.
  With uncertain arrival timing, offer exclusions only for independently supported airborne identities.
  Retain restoration-only reviews for existing exclusions through the first ground observation; never add their unsupported days to flight indicators.
  Preserve pending-flight points, authoritative days, and conflicting identities. Guard: `FlightPointCorrectionAssessmentTests`.
- Retain immutable attribution revisions, including revisions that arrive before their samples.
  Preserve bare UUID encoding and use `SampleAttributionRevision.nextUpdatedAt` for correction and reset writes.
  Clear manual overrides and write newer reset tombstones in one transaction.
  Guards: `DayJournalTests` and `LocationHistoryReaderTests`.
- Publish issues, recording completeness, informational reviews, completed flight history, and deadlines as one scan result.
  Keep unresolved recording dates out of missing-history and whole-day travel inference; retain unrelated issues.
  Unknown assignments block inference only on possible dates within the assessed scope. Never count those dates as assigned candidates.
  Derive historical flights before dismissal filtering. Reuse the same trajectory assessment.
  Determine correction readiness per flight, including flights on the same day.
  Keep pending-flight samples out of proposals and pending flights out of actionable counts.
  Retain pending flight information after applying or dismissing another flight's proposal on that day.
  Guards: `SampleCorrectionAssessmentTests`, `SampleCorrectionCoordinatorTests`, and `GPSCorrectionReviewTests`.
  Dismiss a ready review with its issue when no pending flight remains.
  Never let an invalidated scan restore cached data. Guard: `DataIssueScannerTests`.
- Read historical issue inputs under one outer store snapshot before publishing or caching any year.
  Include the current year and every discovered history year. Keep annual context within supported logical dates.
  Share detector assessment with annual scans. Deduplicate continuous recording concerns across year boundaries while preserving each original query.
  Invalidate both caches together. Reject cancelled completions and retry invalidated historical reads. Guards: `DataIssueScannerHistoryTests` and `HistoricalDataIssueScanResultTests`.
- Run presentation deadlines only in the foreground. Do not add background polling.
- Group recording concerns only across overlapping or adjacent absolute periods. Preserve every problem, candidate date, unknown assignment, and full policy version.
  A derived issue ID does not replace the original review scope when boundaries change. Guard: `RecordingIssueTests`.
- Reassess every original absolute period before completing queued recording work. Include current device evidence regardless of original device IDs or logical-year labels.
  Preserve bounded choice periods separately from merged issue context. Reject different service scopes, generations, majors, or incomplete coverage. Guard: `RecordingReviewQueueTests`.
  Read those periods through the shared history reader in one store snapshot. Reject cancelled completions and retry invalidated results. Guard: `DataIssueScannerTests`.
- Persist notification review context independently of ephemeral scanner scopes. Validate decoded periods and query bounds before use.
  Restore only for the same account/container/store and generation, a compatible major, and complete fresh coverage of the original periods.
  Keep saved contexts immutable and backup-excluded. Propagate storage errors; only missing files mean absence.
  Guards: `RecordingReviewNotificationTests` and `FileRecordingReviewNotificationStoreTests`.
