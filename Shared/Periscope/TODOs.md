# Periscope todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- feat: Add log viewer to settings page"
- Nest tasks that depend on other tasks.
- Don't delete completed tasks, move them to the "Completed issues" section at the bottom.

# Open issues

## P0s (Must do)
- feat: Implement `SpanRelaunchPolicy.survivesRelaunch` resume mechanics. The policy is already recorded on `SpanBegan` payloads and the relaunch sweep honors it (surviving spans are left open, not orphan-closed), but nothing re-seeds them: `end(for:)` in the new process warns "without a matching begin". Needs an async bootstrap step at store/system startup that queries unmatched surviving `SpanBegan` events and re-opens them in `Periscope.openSpans` — plus wall-clock durations for resumed spans (`ContinuousClock` instants don't survive reboot; `SpanEnded.duration` is already optional for this) and accepting that signpost intervals can't resume.
- perf: `events(matching:)` faults `tags` and `attachments` relationships per fetched row (N+1). Set `relationshipKeyPathsForPrefetching` on the fetch descriptors. (Code review finding 8.)
## P1s (Should do)
- fix: Run redaction after the level-floor check in `Periscope.record` — today user redaction code executes (and touches PII) for records the floor is about to discard.
- fix: PeriscopeTools/PeriscopeUI don't compile for native macOS (`navigationBarTitleDisplayMode`, `.topBarTrailing`) even though `Package.swift` advertises `.macOS(.v26)` for all products. Nothing in CI builds them for macOS today, so this is a latent break for the first macOS consumer (`LogViewerUI` has the same issue as precedent). Either gate the iOS-only modifiers or stop advertising macOS for the UI modules.
- fix: The tracer window (`LogQuery.end = origin.date`) is inclusive and sequence isn't in the predicate, so same-millisecond events *after* the origin appear in "leading up to it".
- test: Seeded fuzz/adversarial test for the pipeline state machine (concurrent emit + `add(sink:)` + flush + drop interleavings), per the repo convention for many-branch machinery.
- feat: Optional budget for `measure` spans (`log.measure(.saveEvent, budget: .seconds(1))`) — closure spans can't leak, but "this save should never take >1s" deserves the same overdue signal `begin` spans get.

## P2s (Nice to have)
- fix: `NetworkPathAmbientSource.start` called twice silently replaces the boxed monitor without cancelling the old one; ambient sources in general have no stop/double-start story.
- refactor: `PeriscopeViewer`/`LogInspectorView`/`LogTraceView` capture their model via `State(initialValue:)`; a parent that later passes a different store/origin keeps the stale model. Fine for dev tools — document or key the views.
- fix: `PeriscopeInspector` syncs one-way after init; direct writes to `Periscope.isInspectModeEnabled` don't reflect back into the observable mirror.
- feat: An "open spans" developer surface (viewer section listing currently-open spans with age and budget) — the data exists in `Periscope.openSpans`.
- feat: Surface span exits in the viewer beyond the message text (badge tint by exit mode, filter by exit).
- test: `PeriscopeAlerterTests.startingTwiceDoesNotDuplicateAlerts` asserts after a single `Task.yield()`, so a duplicate could land just after the assertion passes — wait for a sentinel instead.
- docs: `log(PhotoLogs.self) { event }` parses as one call and fails to compile; document the required two-step spelling near `callAsFunction`.
- perf: `LocalNotificationAlertHandler` requests notification authorization on every alert; cache the grant.

# Completed issues

## P0s (Must do)
- fix: Roll back failed `PeriscopeStore` saves so one poisoned batch can't wedge every subsequent save; recovery drops row caches and refetches the session row by identity. (Code review finding 1.)
- fix: Key `InstanceScopeRegistry` by `InstanceID` (pointer + type) and evict entries via associated-object deallocation trackers, so recycled pointers can't inherit a dead object's logging identity. (Code review finding 2.)
- fix: Subscribe to `store.changes()` before the initial load in `PeriscopeViewerModel`/`LogInspectorModel`, so commits landing mid-load can't be missed. (Code review finding 3.)
- fix: Coalesce auto-flushes — one task per error storm with a single follow-up, instead of one task per qualifying record. (Code review finding 4.)
- fix: Bound `liveRecords()` observer buffers with `.bufferingNewest` (`Configuration.liveBufferCapacity`) so a slow consumer can't grow memory without bound. (Code review finding 5.)
- feat: Span lifecycle — `SpanLifetime` (scoped/bounded/indefinite) with a watchdog that expires over-budget spans, `SpanExit` modes (success/failure/cancelled/superseded/expired/orphaned) with derived exits for `measure`, re-begin superseding instead of locking out, and relaunch orphan-closing per `SpanRelaunchPolicy`. (Code review finding 6.)
- perf: Rewrite `Periscope.chunked(_:)` to accumulate runs in mutable buffers — the last-chunk-rewrite approach copied the accumulated chunk per item and went quadratic on large backlogs. (Code review finding 7.)
