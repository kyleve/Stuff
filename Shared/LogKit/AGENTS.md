# LogKit – Module Shape

LogKit is a logging **facade**: a `LogChannel` fans each call out to Apple
unified logging (`os.Logger`) and, in DEBUG builds, to an in-memory `LogStore`
ring buffer that an in-app viewer reads. See [`README.md`](README.md) for the
narrative and API.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **Foundation + os**. It must **not** import SwiftUI, UIKit, WhereCore,
  or any app code — the SwiftUI viewer lives in
  [`LogViewerUI`](../LogViewerUI), and app-specific wiring (shared store,
  typed categories) lives in the consuming facade (e.g. `WhereLog`).

## Invariants

- **Two sinks, one call.** `LogChannel` always calls `os.Logger`; the
  `LogStore` write is `#if DEBUG` only, so release builds never retain log
  text in memory. App call sites log through `LogChannel`, not direct
  `LogStore.record`.
- **Recording never hops actors** — `LogStore` is lock-guarded so any thread
  can `record` synchronously; observers get snapshots via self-unregistering
  `changes()` streams.
- **`warning` maps to `OSLogType.default`**, not `.error` — intentional, so
  warnings don't inflate Console error-level queries. `LogLevel` case order
  *is* severity order (`Comparable` by `rawValue`); keep it intact.
- **The privacy trade-off is deliberate.** `LogChannel` takes an
  already-rendered `String` logged as `.public` (that's what lets the buffer
  capture text). The contract is PII-free messages; don't add
  `privacy:`-style APIs or start logging user content to "fix" it.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`. Each test uses
its own fresh `LogStore` (the production shared store is process-global).
