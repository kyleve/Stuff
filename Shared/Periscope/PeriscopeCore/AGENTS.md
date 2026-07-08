# PeriscopeCore – Module Shape

PeriscopeCore is the core of the **Periscope** observability framework: typed
`Codable` log events, the `Log<Event>` scope hierarchy, tags, spans, the sink
pipeline, ambient event sources, and the SwiftData store. See
[`README.md`](README.md) for the narrative and API.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + os + SwiftData + Network only.** No SwiftUI, no app code, no
  LogKit. UIKit is allowed **only** inside `#if canImport(UIKit)` for ambient
  sources (memory warnings, background/foreground).
- Layering: `PeriscopeUI` and `PeriscopeTools` depend on this module — never
  the reverse.

## Invariants

- **Emitting never blocks the caller.** Log calls append to a lock-guarded
  buffer synchronously; sinks (OSLog, SwiftData) drain asynchronously.
- **Persistence must retain the full hierarchy** — events reference scopes
  many-to-many (links), and scopes keep their parent chain.
- **Custom levels are values, not cases.** `LogLevel` is a struct ordered by
  `severity`; never switch exhaustively over "all" levels.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeCoreTests`). Use in-memory stores, fresh `Periscope` systems per
test (never the shared singleton), and injected clocks.
