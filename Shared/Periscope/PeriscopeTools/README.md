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

- **`PeriscopeViewer(store:title:)`** — the log viewer, pushed inside an
  existing `NavigationStack`. A nav-bar segmented control switches between two
  surfaces (one stack owns the bar and all drill-ins — not a nested `TabView`):
  - **Logs** — newest-first list over a `PeriscopeStore`, searchable,
    filterable by level / event type / scope subtree / session / span exit,
    paged, with exit-mode chips on span rows, per-event detail (exit + reason,
    payload JSON, tags, attachments, and the **ambient state** the event was
    stamped with), NDJSON export (ambient state included, headed by one
    `"record": "session"` line per referenced session carrying its build
    attributes), and a
    comfortable/compact **row-density** picker (persisted). The session filter
    names each session by its build — commit and optimization level when the
    session recorded them, so weeks-old logs can be tied to the code that
    produced them.
  - **Hierarchy** — the scope tree (see `LogHierarchyView`).
- **`LogHierarchyView(store:)`** — the scope-tree browser: the store's
  `LogScope` hierarchy (the tree the `Log<Event>` API builds in code) as an
  expandable outline with per-scope subtree counts; tapping a scope drills
  into its subtree's events with rows indented to mirror the nesting. Shown as
  the viewer's Hierarchy surface, and usable standalone.
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
- **`SpanTreeView(store:)`** — the durable span tree: the store's
  `SpanBegan`/`SpanEnded` pairs nested by time containment (a span inside
  another's lifetime becomes its child) with durations and exit chips, each
  drilling into the span's detail. Distinct from `OpenSpansView` (live,
  in-flight) — this reads the store, so it shows finished spans. Reachable
  from the viewer's Logs toolbar (the **Spans** menu), and usable standalone.
- **`SpanHistoryView(store:)`** — span timing history: the store's closed
  spans grouped by kind (`SpanEnded.name`), each row showing the recorded
  instance count and the p50/p90/p95/p99 of their durations (nearest-rank, so
  every figure is a real observed sample; a kind whose instances never recorded
  a duration reports none). Tapping a kind drills into every closed span of
  that kind, newest first, each linking to its detail and the tracer. A
  **build scope** picker narrows which sessions the percentiles pool — all
  builds, this session only, or every session built at the current one's
  optimization level — because a p95 mixing an `-Onone` build with an `-O` one
  measures nothing; the active scope is named above the list. Reachable
  from the viewer's Logs toolbar (the **Spans** menu), and usable standalone.

## Design system

Appearance — row geometry, badge chrome, typography, and the severity / span-exit
/ inspect color palette — lives in `PeriscopeStylesheet`
([`Sources/Styling/`](Sources/Styling)), a Broadway `BStylesheet`, rather than
inline in views. Each public tool view seeds `periscopeBroadwayRoot()` and reads
tokens via `@Environment(\.stylesheet)`, so the tooling styles correctly with or
without a host-app Broadway root. Row density (`comfortable` / `compact`) is a
stylesheet axis carried on `\.logRowDensity`.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeToolsTests` bundle): models are driven directly over in-memory
stores (`@_spi(Testing) PeriscopeStore.inMemory`), views host via
`TestHostSupport.show`. Run with `./test PeriscopeToolsTests`.

How the tools render is pinned by image snapshots in
[`SnapshotTests/`](SnapshotTests), with reference images under
`SnapshotTests/__Snapshots__/` in Git LFS. They build as the module's own
`PeriscopeToolsSnapshotTests` bundle, which runs alongside every other module's
image suite in the shared `StuffSnapshotTests` scheme. Run with
`./test --snapshots`; to re-record
after an intentional UI change, see the
[SnapshotKitTesting README](../../SnapshotKitTesting/README.md#recording).
