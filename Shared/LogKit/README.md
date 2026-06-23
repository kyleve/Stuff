# LogKit

A tiny logging facade that fans a single call out to **Apple unified logging**
(`os.Logger`, for Console.app) and, in **DEBUG builds**, an **in-memory ring
buffer** an in-app log viewer can read. Get a channel, call `info` / `warning` /
`error`, and the line shows up both in Console and (in DEBUG) in a process-wide
buffer.

LogKit depends only on **Foundation + os** — no app code, no UI. The SwiftUI
viewer that renders the buffer lives in a separate module,
[`LogViewerUI`](../LogViewerUI).

## What you get

- **One call, two sinks** — every message goes to `os.Logger` (all builds) and,
  in DEBUG, into a `LogStore` buffer. Release builds pay only the `os` cost; the
  buffer is compiled out at the call site.
- **A typed severity ladder** — `LogLevel` (`debug` → `info` → `notice` →
  `warning` → `error` → `fault`), `Comparable` by severity, each mapped to an
  `OSLogType`.
- **A bounded, thread-safe buffer** — `LogStore` is a `Sendable` ring buffer
  (default capacity 1000) that records from any thread and streams snapshots to
  observers via `AsyncStream`.

## Installation

`LogKit` is a local SPM library in this repo (`Shared/LogKit`). Add it to a
target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "LogKit")])
```

## Quick start

Build a `LogStore` you keep for the process, then make a `LogChannel` per
category pointed at it:

```swift
import LogKit

let store = LogStore()
let channel = LogChannel(subsystem: "com.example.app", category: "Networking", store: store)

channel.info("Request succeeded")
channel.warning("Falling back to cache")
channel.error("Request failed: \(error.localizedDescription)")
```

Most apps don't pass the store around by hand — they wrap this in a small facade
that owns the shared store and a typed category enum (see the Where app's
`WhereLog` in `WhereCore`).

## Public API

```swift
public enum LogLevel: Int, Sendable, Comparable, CaseIterable, Codable {
    case debug, info, notice, warning, error, fault
    public var osLogType: OSLogType { /* debug/info/default/default/error/fault */ }
}

public struct LogEntry: Sendable, Identifiable, Hashable {
    public let id: UUID, date: Date, level: LogLevel
    public let subsystem: String, category: String, message: String
}

public final class LogStore: Sendable {
    public init(capacity: Int = 1000)
    public func record(_ entry: LogEntry)
    public func snapshot() -> [LogEntry]            // oldest first
    public func clear()
    public func changes() -> AsyncStream<[LogEntry]> // current snapshot, then one per change
}

public struct LogChannel: Sendable {
    public init(subsystem: String, category: String, store: LogStore? = nil)
    public func debug/info/notice/warning/error/fault(_ message: @autoclosure () -> String)
}
```

## How it works

`LogChannel.emit` does two things: it calls `os.Logger.log(level:)` (always),
then — `#if DEBUG` only — appends a `LogEntry` to its `LogStore`. The store
guards its state with an `OSAllocatedUnfairLock` (so `record` never hops to the
main actor) and notifies observers by yielding a fresh snapshot into each
registered `AsyncStream`; observers are unregistered automatically when their
stream's consumer cancels. Past `capacity`, the oldest entries are evicted.

## The privacy trade-off

`LogChannel` takes an **already-rendered `String`**, not an `os` interpolation.
That's what lets it capture the text for the buffer, but it means per-argument
`os` privacy annotations (`privacy: .public` / `.private`) aren't available — the
whole message is logged as `.public`. **Keep PII out of log messages**; use this
for operational diagnostics only.

`warning` has no dedicated `os` level, so it maps to `OSLogType.default` (same as
`notice`). It reads as a distinct level in the in-app viewer without inflating
Console's error-level queries.

## Testing

Swift Testing in a hosted bundle (`LogKitTests`). Drive a `LogChannel` backed by
a fresh `LogStore` and assert on `snapshot()` (level/message ordering), the
capacity eviction, `clear()`, and that `changes()` yields the initial snapshot
then one per `record`/`clear`.
