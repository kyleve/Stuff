# PortholePeriscope

PortholePeriscope is a [Porthole](../) connector that exposes an app's
[Periscope](../../Periscope) logs over the bridge — a queryable event history, a
live event tail, and the scope tree.

## Using it

```swift
import PortholePeriscope

porthole.register(PeriscopeConnector(store: logStore, system: .shared))
```

## Surface (id `periscope`)

- Data source `events` — stored log events, newest first. Filters:
  `minimumLevel`, `eventName`, `messageContains`, `start`, `end`,
  `afterSequence`. Page with `limit` + `cursor` (an offset).
- Data source `live-events` (subscribable) — a live stream of events as they're
  emitted.
- Data source `scopes` — the scope hierarchy (id, name, parent).

Rows carry the decoded event payload as JSON when it decodes, plus level,
message, scopes, and the `externalID` (the `store://` / `region://` object key).

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholePeriscopeTests`). Seeds an in-memory `PeriscopeStore`, asserts the
event/level/message filters and the scope list, and drives a live `Periscope` to
confirm `live-events` streams an emitted record.
