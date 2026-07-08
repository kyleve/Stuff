# PeriscopeTools

On-device log exploration for the **Periscope** observability framework
([`PeriscopeCore`](../PeriscopeCore)): a searchable latest-logs viewer, a
tracer that follows an error back through time and up the scope tree, a
hookable debug toast for warnings and errors, and a "log view mode" that
reveals the events behind any wrapped view.

## Installation

`PeriscopeTools` is a local SPM library in this repo
(`Shared/Periscope/PeriscopeTools`). Add it to a target's dependencies in
[`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeTools")])
```

## Quick start

All tools are developer surfaces — gate them behind `#if DEBUG` or a
developer menu.

```swift
// The viewer, pushed from a developer settings screen:
NavigationLink("Logs") {
    PeriscopeViewer(store: store, title: "Logs")
}

// The debug toast, started once at launch:
let alerter = PeriscopeAlerter(
    system: .shared,
    threshold: .warning,
    handler: LocalNotificationAlertHandler(),
)
alerter.start()

// Log view mode, wired at the root and toggled from developer settings:
RootView().periscopeInspector(inspector)          // PeriscopeInspector
PaymentRow(payment).logInspectable(payment)       // any Log or provider
Toggle("Log View Mode", isOn: $inspector.isEnabled)
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
- **`PeriscopeAlerter(system:threshold:handler:)`** — the debug toast
  engine: watches a system's live records and routes everything at the
  threshold or above to a `PeriscopeAlertHandler`. The built-in
  `LocalNotificationAlertHandler` posts a local notification (provisional
  authorization, delivered quietly); apps with their own toast system
  conform to the protocol instead.
- **Log view mode** — `PeriscopeInspector` (observable wrapper over
  `Periscope.isInspectModeEnabled` plus the store), injected via
  `View.periscopeInspector(_:)`. `View.logInspectable(_:)` (taking a `Log`
  or a `LogContextProviding` model) badges the view while the mode is on;
  tapping the badge presents every stored event in that context's scope
  subtrees, live-refreshing, each linking into detail and the tracer.
- **`OpenSpansView(system:)`** — every span currently open via
  `begin(for:)`, longest running first, with ticking ages, lifetimes, and
  scope paths. Reads the system (open spans are live state, not store
  history); push it from a developer menu.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeToolsTests` bundle): models are driven directly over in-memory
stores (`@_spi(Testing) PeriscopeStore.inMemory`), views host via
`WhereTesting.show`. Run with `tuist test PeriscopeToolsTests`.
