# LogViewerUI

A small, app-agnostic SwiftUI **log viewer** over one or more [`LogKit`](../LogKit)
`LogStore`s. Point it at a buffer (or several) and it renders captured entries
newest-first with a level badge, category, timestamp, and message, plus live
search, level/category filtering, share, copy, and clear — for *any* `LogStore`,
with no per-app code. Multiple buffers are merged chronologically, so a host can
surface several modules' logs (each with its own subsystem/category) in one view.

It's built for **developer / DEBUG surfaces** (think a hidden "Logs" row in a
Settings screen): it reads whatever the app's loggers wrote into the shared
buffer(s) this session.

LogViewerUI depends only on **SwiftUI + Observation + UIKit (pasteboard) +
LogKit** — no app code.

## What you get

- **Live list** — entries newest-first; each row shows a tinted level badge, the
  (display-mapped) category, an `HH:MM:SS` timestamp, and a selectable message.
  The list updates as new lines are logged (it observes `LogStore.changes()`).
- **Filtering & search** — a minimum-level picker, a category picker (built from
  the categories actually present), and a `.searchable` field matching message
  *or* the mapped category display name.
- **Share / copy / clear** — share or copy the currently-filtered entries as
  plain text (ISO-8601 timestamps; formatting deferred until share is initiated),
  copy a single message from its context menu, or clear the buffer (with
  confirmation).
- **Empty states** — a `ContentUnavailableView` when nothing has been captured,
  and a separate one when filters match nothing.

## Installation

`LogViewerUI` is a local SPM library in this repo (`Shared/LogViewerUI`). Add it
to a target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourUI", dependencies: [.target(name: "LogViewerUI")])
```

## Quick start

Drop `LogViewer` into a navigation context you own and hand it a configuration
built from your store:

```swift
import LogViewerUI

NavigationStack {                       // the viewer expects an ambient stack
    LogViewer(configuration: LogViewerConfiguration(store: myLogStore, title: "Logs"))
}
```

The view loads the current snapshot on appear and streams updates while it's on
screen.

> `LogViewer` sets a navigation title and toolbar but **doesn't** create its own
> `NavigationStack`, so it composes inside a settings screen, tab, or sheet.

## Configuration

```swift
public struct LogViewerConfiguration: Sendable {
    public init(
        stores: [LogStore],
        title: String = "Logs",
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    )

    /// Convenience for the common single-buffer case.
    public init(
        store: LogStore,
        title: String = "Logs",
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    )
}
```

- **`stores`** — the `LogKit` buffer(s) to read and observe, merged
  chronologically. The `store:` init is a convenience for the single-buffer case.
- **`title`** — the viewer's navigation title.
- **`categoryDisplayName`** — maps a raw `LogEntry.category` to a friendly name
  (e.g. an app's typed-category enum → a label). Defaults to identity.

## How it works

`LogViewer` owns a `@MainActor @Observable LogViewerModel` that mirrors the
store(s) into `entries` and derives cached `filteredEntries` (newest-first, after
level/category/search). Observation starts in the model's `init` and iterates
each store's `LogStore.changes()` concurrently (in a task group) until the model
is deallocated, remerging the per-store snapshots by timestamp on every change —
so the list stays live without the view touching the lock-guarded stores
directly. Recording stays off the main actor in `LogKit`; this module only
consumes snapshots on the main actor for display.

## Example: adopting it in an app (Where)

The Where app exposes it behind a DEBUG-only entry in its floating developer
overlay, pointed at both process-wide buffers — `WhereLog` (the app/WhereCore
facade) and `RegionLog` (RegionKit) — merged into one list:

```swift
#if DEBUG
NavigationLink {
    LogViewer(configuration: LogViewerConfiguration(
        stores: [WhereLog.store, RegionLog.store],
        title: Strings.settingsDebugLogsTitle,
    ))
} label: {
    Label(Strings.settingsDebugLogsLink, systemImage: "ladybug")
}
#endif
```

## Testing

Swift Testing in a hosted bundle (`LogViewerUITests`). Seed a `LogStore`, drive
`LogViewerModel` (filters, `exportText`, `clear`), and assert on
`filteredEntries`; plus hosting tests that mount `LogViewer` for the populated
and empty states.
