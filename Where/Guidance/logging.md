# Logging contracts

Use Periscope's `@LogScope`, `@LogEvent`, and classified `@LogField` payloads through `WhereLog`.
Keep each module's `*Log.swift` declarations in `Sources/Logging/`; do not write direct `LogEvent` conformances or raw-string events.

- Events log `.public`: keep PII out. Use `info` for important success, `warning` for handled degradation, and `error`/`fault` for failure. Keep hot paths quiet.
- Match classified fields with `.shared` or `.restricted` inputs. Pass original errors through `.restricted(.errorDetails, error)` without a duplicate attachment.
- RegionKit uses its own root in the same `Periscope.shared`. Only the app process attaches a store; widgets/share extensions use OSLog only. App Intents run in the app process.
- Events about store objects stamp `externalID` with their `store://` identity. RegionKit uses `region://`; see its [contract](../RegionKit/AGENTS.md).

## Spans

Measure expensive work with the owning logger's `measure(.name, budget:)`.
This includes bulk reads/commits, aggregation, calendar layout, issue detection, reconciliation, backup, GPS acquisition, and orchestration that reflects user-perceived latency.
Do not span SwiftUI computed properties evaluated on every `body` pass.

- Names are a nested typed `SpanName` enum. Associated values need readable `CustomStringConvertible` output, such as `detect(border-drift)`.
  A scope may have spans without events; derive its logger through the owning `WhereLog` group.
- Budgets live beside the work. An overrun warns while the span continues; it is not a timeout.
  Omit the budget only when no ceiling is meaningful, such as user-driven backup work whose cost scales with the archive.
- Launch/reset steps conform to `BudgetedLaunchStep` and join through `.measured()`. Declare the budget without adding another `measure` call.
  `MeasuredStep` is not budgeted. Gates are exempt because they wait for user input.
- Detectors name their span through `DataIssueDetecting.detects`; `DataIssueScanner` owns detector-pass and shared GPS-assessment measurements.
- Spans begun before the durable store attaches are half-persisted: the begin reaches OSLog, while the end reaches the store.
  Keep that fix in Periscope ([backlog](https://linear.app/kve/view/c0511a6281eb)); do not add a Where workaround.
