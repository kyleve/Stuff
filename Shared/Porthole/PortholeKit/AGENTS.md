# PortholeKit – Module Shape

PortholeKit is the device-side Porthole runtime: the `Porthole` composition
root, the `PortholeConnector` protocol (+ `PortholeAction` / `PortholeDataSource`),
the connector registry, the per-connection session router, the built-in `app`
connector, and (in the network layer) the Bonjour listener and pairing manager.
See [`README.md`](README.md) for usage and how to write a connector.

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read that
first.

## Scope & dependencies

- Depends only on **PortholeCore** (+ `Network`/`UIKit` from the SDK). It must
  **not** depend on PeriscopeCore or any app module — the Periscope, SwiftData,
  and Where connectors are *separate* modules that depend on PortholeKit, never
  the reverse. Logging is PortholeKit's own `os.Logger` (`PortholeLog`), not
  Periscope.
- Built-in connectors live in `Sources/Connectors/`. `app` (AppInfoConnector)
  ships here; `ui`, `files`, `notifications`, `permissions` are added in their
  own steps and self-register in `Porthole.init`. iOS-only connectors are
  wrapped in `#if canImport(UIKit)`.

## Invariants

- **One `Porthole` per app, created at the composition root and injected** — no
  singleton. It is `@MainActor`/`@Observable`; UI binds to `state`.
- **A duplicate connector id is a programmer error** (`assertionFailure` in
  debug, ignored in release) — connector ids are a fixed curated set.
- **The runtime validates parameters/filters against the connector's
  `PortholeSchema` before dispatch**; a handler `throw` becomes
  `.failure(.handlerFailed)`, never a crash and never a swallowed error.
- **Dispatch runs off a `Sendable` snapshot** (`ResolvedConnectors`) built once
  per session — derive, don't re-resolve per request or hop to the main actor.
- **Subscriptions are bounded** (drop-oldest at 256) so a fast producer can't
  grow memory without limit; every subscription's tasks are cancelled when it's
  unsubscribed or the connection closes (every start has a stop).
- **The request router is transport-agnostic** and tested over
  `LoopbackTransport` via `attach(transport:)`; keep the real network transport
  (`NWConnectionTransport`) and Bonjour listener (`PortholeServer`) thin adapters
  so the tested core carries the logic.
- **The pairing/session handshake (`DevicePairingManager`) is pure of `Network`
  types** so it runs over loopback in tests: one human code active at a time,
  wrong guesses accumulate and burn it after 3, it expires after 120 s, and the
  code is published (awaited) *before* the challenge is sent. A session
  re-derives a fresh key from the stored PSK; the `PortholeSecureChannel` then
  continues the *same* frame reader (see `TransportFrameReader`) so the plaintext
  handshake and the encrypted session share one connection without a second
  iterator.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeKitTests`). Drive sessions in-process via `attach(transport:)` and the
`TestSessionClient` helper; wait on delivered events, never sleep. The
duplicate-id assertion is intentionally not unit-tested (it traps in debug, as
designed for a programmer error).
