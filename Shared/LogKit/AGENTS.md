# LogKit – Module Shape

LogKit is a logging **facade**: a `LogChannel` fans each call out to Apple
unified logging (`os.Logger`) and, in DEBUG builds, to an in-memory `LogStore`
ring buffer that an in-app viewer reads. It owns the severity ladder
(`LogLevel`), the captured-line value (`LogEntry`), the buffer (`LogStore`), and
the channel (`LogChannel`). See [`README.md`](README.md) for the narrative and
usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **Foundation + os**. It must **not** import SwiftUI, UIKit, WhereCore, or
  any app code — the SwiftUI viewer lives in [`LogViewerUI`](../LogViewerUI), and
  app-specific wiring (shared store, typed categories) lives in the consumer
  (e.g. `WhereLog` in `WhereCore`).
- Library target only ([`Package.swift`](../../Package.swift),
  `Shared/LogKit/Sources`); the hosted test bundle `LogKitTests` is wired in
  [`Project.swift`](../../Project.swift) via the `unitTests` helper (host:
  `StuffTestHost`).

## Public API (the whole surface)

- [`LogLevel`](Sources/LogLevel.swift) – `debug, info, notice, warning, error,
  fault`. `Comparable` **by `rawValue`**, so case order *is* severity order;
  `osLogType` maps each to an `OSLogType`.
- [`LogEntry`](Sources/LogEntry.swift) – one captured line (`id`, `date`,
  `level`, `subsystem`, `category`, already-rendered `message`). `Sendable`,
  `Identifiable`, `Hashable`.
- [`LogStore`](Sources/LogStore.swift) – the `Sendable` bounded ring buffer:
  `record`, `snapshot()` (oldest first), `clear()`, and `changes()` (an
  `AsyncStream` that yields the current snapshot then one per mutation).
- [`LogChannel`](Sources/LogChannel.swift) – the facade: `init(subsystem:
  category:store:)` and one method per level. `store` is optional so a channel
  can target `os` only.

## Invariants & behaviors to preserve

- **Two sinks, one call.** `LogChannel.emit` always calls `os.Logger`; the
  `LogStore.record` is `#if DEBUG` only, so release builds never retain log text
  in memory. Don't move the buffer write outside the `#if DEBUG`.
- **Recording never hops actors.** `LogStore` is guarded by an
  `OSAllocatedUnfairLock`, not an actor or the main actor, so any thread can
  `record`. Observers are notified by yielding a fresh `[LogEntry]` snapshot into
  each registered `AsyncStream`; keep `record`/`clear` synchronous and
  lock-scoped (collect continuations under the lock, yield outside it).
- **`changes()` self-unregisters.** Each stream registers a continuation keyed by
  a `UUID` and clears it in `onTermination`. Preserve that so a cancelled
  consumer doesn't leak a continuation. The initial snapshot is yielded *before*
  registering the observer so concurrent `record` calls cannot deliver an update
  ahead of the initial yield.
- **Capacity eviction is oldest-first** and `capacity` must stay `> 0`
  (precondition in `init`).
- **Direct `record` is for tests and `LogChannel`.** App call sites should log
  through `LogChannel`, which only writes to the store in DEBUG builds. Direct
  `LogStore.record` always retains text regardless of build configuration.
- **`warning` maps to `OSLogType.default`**, not `.error` — intentional, so
  warnings don't inflate Console error-level queries while still reading as a
  distinct level in the viewer. Keep `LogLevel`'s case order intact:
  `Comparable` and the viewer's level filter both rely on it.

## The privacy trade-off (don't undo it)

`LogChannel` takes an already-rendered `String`, so it logs the whole message as
`.public` and per-argument `os` privacy isn't available. This is deliberate (it's
what lets the buffer capture the text). The contract is **PII-free messages**;
don't add `privacy:`-style APIs or start logging user content to "fix" it.

## Conventions

- Follow the root rules: exhaustive `switch` over enums (no bare `default:`),
  small named structs over tuples, `Hashable`/typed identifiers over raw strings
  at call sites.
- Keep this module UI-free and app-free; new rendering belongs in `LogViewerUI`,
  new app wiring in the consuming facade.

## Testing

Swift Testing in [`Tests/`](Tests) (never XCTest), hosted in `StuffTestHost`.
Patterns: drive a `LogChannel` over a fresh `LogStore` and assert level/message
order via `snapshot()`; cover capacity eviction and `clear()`; and assert
`changes()` yields the initial snapshot then one per `record`/`clear`. Each test
uses its own `LogStore` (the production shared store is process-global).
