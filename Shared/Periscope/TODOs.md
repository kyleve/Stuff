# Periscope todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- feat: Add log viewer to settings page"
- Nest tasks that depend on other tasks.
- Don't delete completed tasks, move them to the "Completed issues" section at the bottom.

# Open issues

## P0s (Must do)
- feat: Implement `SpanRelaunchPolicy.survivesRelaunch` resume mechanics. The policy is already recorded on `SpanBegan` payloads and the relaunch sweep honors it (surviving spans are left open, not orphan-closed), but nothing re-seeds them: `end(for:)` in the new process warns "without a matching begin". Needs an async bootstrap step at store/system startup that queries unmatched surviving `SpanBegan` events and re-opens them in `Periscope.openSpans` — plus wall-clock durations for resumed spans (`ContinuousClock` instants don't survive reboot; `SpanEnded.duration` is already optional for this) and accepting that signpost intervals can't resume.

## P1s (Should do)
## P2s (Nice to have)
- feat: An "open spans" developer surface (viewer section listing currently-open spans with age and budget) — the data exists in `Periscope.openSpans`.
- feat: Surface span exits in the viewer beyond the message text (badge tint by exit mode, filter by exit).
- docs: `log(PhotoLogs.self) { event }` parses as one call and fails to compile; document the required two-step spelling near `callAsFunction`.
- perf: `LocalNotificationAlertHandler` requests notification authorization on every alert; cache the grant.

# Completed issues

## P2s (Nice to have)
- fix: `NetworkPathAmbientSource.start` cancels the prior monitor when restarted (it used to keep running and logging forever); `AmbientEventSource.start` documents its called-exactly-once contract.
- refactor: Tool views (`PeriscopeViewer`, `LogInspectorView`, `LogTraceView`, `LogEventDetailView`) rebuild their models when identity-relevant inputs change in place — `.task(id:)` keyed on store identity plus each view's inputs, verified by a store-swap hosting test against `changes()` observer counts.
- fix: `PeriscopeInspector` now mirrors both ways — direct writes to `Periscope.isInspectModeEnabled` flow back through the new `inspectModeChanges()` stream, with no-change guards on both sides keeping the loop stable.

## P1s (Should do)
- fix: Check level floors before running redaction in `Periscope.record` — redaction code no longer executes (touching PII) for records the floor discards; floors apply to the record as emitted.
- fix: PeriscopeTools/PeriscopeUI used iOS-only API while the package advertised `.macOS(.v26)`. Resolved from the other side: Foreman's removal made the package iOS-only, so macOS is no longer advertised anywhere. (Core's `#if canImport(UIKit)` gating stays — it's still correct per-SDK hygiene.)
- fix: The tracer trims its trail to events strictly `(date, sequence)`-before the origin, so same-millisecond events that landed after it (and a traced `SpanBegan`'s own end event) no longer appear under "leading up to it".
- feat: Optional budget for `measure` spans — `log.measure(.saveEvent, budget: .seconds(1)) { … }` emits a `SpanOverdue` warning *while the closure hangs* (per-call sentinel task, cancelled on completion); the span still ends normally with its derived exit.

## P0s (Must do)
- fix: Roll back failed `PeriscopeStore` saves so one poisoned batch can't wedge every subsequent save; recovery drops row caches and refetches the session row by identity. (Code review finding 1.)
- fix: Key `InstanceScopeRegistry` by `InstanceID` (pointer + type) and evict entries via associated-object deallocation trackers, so recycled pointers can't inherit a dead object's logging identity. (Code review finding 2.)
- fix: Subscribe to `store.changes()` before the initial load in `PeriscopeViewerModel`/`LogInspectorModel`, so commits landing mid-load can't be missed. (Code review finding 3.)
- fix: Coalesce auto-flushes — one task per error storm with a single follow-up, instead of one task per qualifying record. (Code review finding 4.)
- fix: Bound `liveRecords()` observer buffers with `.bufferingNewest` (`Configuration.liveBufferCapacity`) so a slow consumer can't grow memory without bound. (Code review finding 5.)
- feat: Span lifecycle — `SpanLifetime` (scoped/bounded/indefinite) with a watchdog that expires over-budget spans, `SpanExit` modes (success/failure/cancelled/superseded/expired/orphaned) with derived exits for `measure`, re-begin superseding instead of locking out, and relaunch orphan-closing per `SpanRelaunchPolicy`. (Code review finding 6.)
- perf: Rewrite `Periscope.chunked(_:)` to accumulate runs in mutable buffers — the last-chunk-rewrite approach copied the accumulated chunk per item and went quadratic on large backlogs. (Code review finding 7.)
- perf: Prefetch the `tags` and `attachments` relationships on `PeriscopeStore` event reads (`relationshipKeyPathsForPrefetching`) so value mapping doesn't fault each relationship per row (N+1). (Code review finding 8.)
- test: Seeded fuzz/adversarial test for the pipeline (concurrent emit + derive + `add(sink:)` + flush interleavings from fixed seeds), asserting no loss/duplication, per-emitter order, and scopes-before-records on every sink.
- test: Cover the drop policy's scope-definitions-never-drop promise by overflowing a gated queue with interleaved definitions and records.
- test: Make the alerter lifecycle tests deterministic via `Periscope.liveObserverCount` (`@_spi(Testing)`) instead of racing duplicate deliveries against a `Task.yield()`.
