# LogViewerUI

A small, app-agnostic SwiftUI **log viewer** over a [`LogKit`](../LogKit)
`LogStore`. Point it at a buffer and it renders captured entries newest-first
with a level badge, category, timestamp, and message, plus live search,
level/category filtering, share, copy, and clear — for *any* `LogStore`, with no
per-app code.

It's built for **developer / DEBUG surfaces** (think a hidden "Logs" row in a
Settings screen): it reads whatever the app's loggers wrote into the shared
buffer this session.

LogViewerUI depends only on **SwiftUI + Observation + UIKit (pasteboard) +
LogKit** — no app code.

## What you get

- **Live list** — entries newest-first; each row shows a tinted level badge, the
  (display-mapped) category, an `HH:MM:SS` timestamp, and a selectable message.
  The list updates as new lines are logged (it observes `LogStore.changes()`).
- **Filtering & search** — a minimum-level picker, a category picker (built from
  the categories actually present), and a `.searchable` field matching message
  *or* category.
- **Share / copy / clear** — share or copy the currently-filtered entries as
  plain text (ISO-8601 timestamps), copy a single message from its context menu,
  or clear the buffer (with confirmation).
- **Empty state** — a `ContentUnavailableView` when nothing has been captured.

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
        store: LogStore,
        title: String = "Logs",
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    )
}
```

- **`store`** — the `LogKit` buffer to read and observe.
- **`title`** — the viewer's navigation title.
- **`categoryDisplayName`** — maps a raw `LogEntry.category` to a friendly name
  (e.g. an app's typed-category enum → a label). Defaults to identity.

## How it works

`LogViewer` owns a `@MainActor @Observable LogViewerModel` that mirrors the store
into `entries` and derives `filteredEntries` (newest-first, after
level/category/search). On appear, the view's `.task` runs `model.observe()`,
which iterates `LogStore.changes()` and assigns each fresh snapshot — so the list
stays live without the view touching the lock-guarded store directly. Recording
stays off the main actor in `LogKit`; this module only consumes snapshots on the
main actor for display.

## Example: adopting it in an app (Where)

The Where app exposes it behind a DEBUG-only entry in Settings, pointed at the
process-wide buffer its `WhereLog` facade writes to, mapping raw categories
through its typed enum:

```swift
#if DEBUG
NavigationLink {
    LogViewer(configuration: LogViewerConfiguration(
        store: WhereLog.store,
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
