# PeriscopeTools

On-device log exploration for the **Periscope** observability framework
([`PeriscopeCore`](../PeriscopeCore)): a searchable latest-logs viewer, a
tracer that follows an error back through time and up the scope tree, a
hookable debug toast for warnings and errors, and a "log view mode" that
reveals the events behind any wrapped view.

> **Status:** the viewer, tracer, and toast have landed; the log view mode
> lands incrementally.

## Installation

`PeriscopeTools` is a local SPM library in this repo
(`Shared/Periscope/PeriscopeTools`). Add it to a target's dependencies in
[`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeTools")])
```

## Public API

- **`PeriscopeViewer(store:title:)`** — the latest-logs viewer: newest-first
  list over a `PeriscopeStore`, searchable, filterable by level / event type
  / scope subtree / session, paged, with per-event detail (payload JSON,
  tags, attachments) and NDJSON export for bug reports. Push it inside an
  existing `NavigationStack`.

- **`LogTraceView(store:origin:)`** — the tracer: from one event (typically
  an error), shows the trail that led up to it — earlier events in the
  subtrees of all its (linked) scopes, events logged at ancestor scopes on
  the way up the tree (never siblings), and its span pair — newest first.
  Reachable from every event detail's Trace button, and each trail row's
  detail can trace further back.

The debug toast and log view mode land incrementally — see the sources for
what exists today.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeToolsTests` bundle). Run with `tuist test PeriscopeToolsTests`.
