# Span contracts

## Spans

Anything plausibly expensive is measured. Use `logger.measure(.name, budget:)`
on the owning type's `*Log`. Then the [Periscope](../../Shared/Periscope) span
history can say which work is slow on a real device. It does not only say that
a screen felt slow.

- **Names are a typed `enum SpanName`** nested on the `*Log`. Never use a raw
  string. When a name carries a value, give it `CustomStringConvertible`. Then
  the history buckets by something readable — `step(resolve-scope)`,
  `loadRegion(us-CA)`, `detect(border-drift)` — not the Swift case's shape.
- **The budget is the promise, and it lives next to the work.** Overrunning it
  emits a `SpanOverdue` warning while the span keeps running. A budget is a
  claim about this specific call ("a widget publish must not take 2s"). It is
  not a timeout. Omit it only where no ceiling is meaningful — user-driven
  backup export/import, which scales with the archive.
- **Launch and reset steps declare a budget, not a `measure` call.** Every step
  in `WhereLaunch`'s plans conforms to `BudgetedLaunchStep`. It joins the plan
  through `.measured()`, which wraps it in `MeasuredStep`. A new step is
  spanned by declaring `budget`. `MeasuredStep` pointedly is not itself
  budgeted. Nothing can be measured twice into nested duplicate spans. Gates
  are exempt. The onboarding gate parks on the user. It has nothing to promise.
- **Span the work, not the property.** Composite orchestration that reflects
  user-perceived latency is worth a span even when its callees have their own
  (`WhereSession.appBecameActive`, `YearReportModel.refreshAll`, an intent's
  `perform`). A SwiftUI computed property re-evaluated per `body` pass is not.
  It would emit continuously and bury the real signal.
- **If a type needs spans but has no events,** declare an `@LogScope` enum
  with its nested `SpanName` and no `@LogEvent` members. See `ReportReaderLog`,
  `DataIssueScannerLog`, and `PresenceCalendarLog`. Derive its logger through
  the owning `WhereLog` group.
- **Spans emitted before a scope's durable store attaches are
  half-persisted.** A `SpanBegan` from the pre-sink window is only in OSLog.
  The `SpanEnded` lands in the store. Durations survive but the pair does not.
  That gap is Periscope's to close (P0 in its
  [Periscope backlog](https://linear.app/kve/view/c0511a6281eb)). Do not work around it here.
