# Flagger – Module Shape

Flagger is the SwiftUI-free feature-flag engine: typed group/source
registration, behavior policies, cached reads, failure streams, and
default-eliding SwiftData persistence. See [`README.md`](README.md).

This complements the root [`AGENTS.md`](../../AGENTS.md).

## Scope & dependencies

- Foundation, os, and SwiftData only; app flag groups and sources stay in consumers.
- One Flagger instance owns one scope and one physical store; create it once at the composition root and inject it down.

## Invariants

- Persist only overrides; writing the current default deletes the row.
- Launch and first-access policies freeze effective values for the instance lifetime; only `LiveUpdating` has public typed mutation and value-stream APIs.
- Sources, group types, and stable flag IDs are unique within a Flagger.
- Synchronous reads touch only `OSAllocatedUnfairLock` state; every SwiftData operation stays in `FlaggerPersistence`.

## Testing

Swift Testing in [`Tests/`](Tests) uses fresh in-memory or temporary-URL stores.
