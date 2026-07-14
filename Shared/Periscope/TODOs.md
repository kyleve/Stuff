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
- fix: After initial merge, we should come back and update the UI to consume the Shared/Broadway design system tooling, eg a PeriscopeStylesheet for components and other recommendations.


## P2s (Nice to have)


# Completed issues


## Second review pass
- fix: Redaction can no longer split span pairs — `SpanBegan`/`SpanEnded` records are transform-only through the hook: returning `nil` records a stripped copy instead (tags and attachments dropped, `SpanEnded.exit.reason` blanked; `strippedOfSensitivePayload`), since a suppressed half would strand its partner. Level floors remain the supported way to silence spans; `SpanOverdue` stays suppressible.
- fix: Live-stream yields moved inside the state lock (`Periscope.buffer`), so `liveRecords()` observers see buffered order — racing emitters could previously invert live delivery (e.g. a span's end before its began; sinks and `recentRecords()` were always ordered). The record/beginSpan delivery choreography now shares one helper so the paths can't drift, with tests covering begans through the `beginSpan` bypass.
- fix: `begin(for:)` registers the span and records its `SpanBegan` atomically (`LogRecorder.beginSpan`), so a racing supersede or `end(for:)` can never deliver a span's end before its began; the span-lifecycle fuzz now asserts strict began-then-ended pairs. The superseded close deliberately follows the *new* began (cause before effect).
- fix: The overflow drop policy exempts span began/ended records (like scope definitions), so drop pressure can never split a recorded pair — no parentless ends, no spans stuck reading "open" until next launch's orphan sweep. `SpanOverdue` stays droppable; the span-lifecycle fuzz runs under a small queue to keep this covered.
- fix: Budgeted `measure` sentinels serialize with the span's end through a per-measure gate, so a sentinel losing the race at the budget boundary can never record a `SpanOverdue` after the `SpanEnded`.
- refactor: The six copies of scope-path walking (OSLogSink, the three tool models, OpenSpansView, NDJSONExporter) collapse into `LogScope.ancestry(of:resolve:)`; display joins with `" / "`, exports with `"/"` — now documented as deliberate.
- fix: `showHosted` runs window animations at 100x and restores them, matching `WhereTesting.show`.
- fix: `PeriscopeViewer` clears its export sheet and failure alert when the store is swapped in place, alongside the model rebuild.
- test: Span-lifecycle fuzz — seeded concurrent interleavings of emits, `begin`/`end` on shared keys (cross-task supersession), global floor flips, and flushes; asserts per-emitter delivery order under floors, no dangling span halves, an empty open-span registry after cleanup, and scopes-before-records.
- fix: `events(matching:)` builds its filter predicate as statements (hand-written `PredicateExpressions`, one `let` per condition) instead of one `#Predicate` macro expression — the macro's single inference tree exceeded the type-checker budget on CI's slower runners, and the statement form also removes the two-variant workaround so every filter (including span exit) combines in one predicate.
- perf: The orphan sweep (app-launch path) fetches only the `spanID` column for its began/ended passes; full rows load exclusively for orphan candidates. (Finding 1.)
- fix: Inspect-mode changes yield inside the state lock so racing setters can't strand `bufferingNewest(1)` subscribers on a stale value. (Finding 2.)
- fix: Span pairs floor together — the begin-time floor decision (`OpenSpan.beganRecorded`) governs the whole lifecycle via `LogRecord.bypassesFloors`; no dangling halves across floor changes. (Finding 3.)
- fix: The span watchdog holds the system weakly (strong promotion per call, never across sleeps), so discarded systems release immediately; adds the missing respawn-on-earlier-deadline test. (Finding 4.)


## P2s (Nice to have)
- fix: `NetworkPathAmbientSource.start` cancels the prior monitor when restarted (it used to keep running and logging forever); `AmbientEventSource.start` documents its called-exactly-once contract.
- refactor: Tool views (`PeriscopeViewer`, `LogInspectorView`, `LogTraceView`, `LogEventDetailView`) rebuild their models when identity-relevant inputs change in place — `.task(id:)` keyed on store identity plus each view's inputs, verified by a store-swap hosting test against `changes()` observer counts.
- fix: `PeriscopeInspector` now mirrors both ways — direct writes to `Periscope.isInspectModeEnabled` flow back through the new `inspectModeChanges()` stream, with no-change guards on both sides keeping the loop stable.
- feat: `OpenSpansView(system:)` — the open-spans developer surface: longest-running first with ticking ages, lifetimes/budgets, and scope paths, over the new `Periscope.openSpans()` snapshot.
- feat: Span exits are first-class in the tooling — an indexed `spanExitMode` column with `LogQuery.spanExitMode` ("everything that failed"), exit-mode chips on rows, an Exit row with the reason in event detail, a viewer filter, and NDJSON export of the mode.
- feat: Derive-and-emit `callAsFunction` overloads — `log(PhotoLogs.self) { … }` and `album(for: id) { … }` now compile as single expressions (Swift resolves a value call's args + trailing closure as one application; type callees like SwiftUI Layouts get an implicit init-then-call split, value callees don't).
- perf: `LocalNotificationAlertHandler` caches its authorization outcome (granted/denied; transient request failures retry) behind an `AlertNotificationCenter` seam modeled on Where's `NotificationReminderCenter`, so error storms don't do a daemon round-trip per alert.


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
