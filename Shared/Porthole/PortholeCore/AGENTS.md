# PortholeCore – Module Shape

PortholeCore is the shared foundation of the Porthole suite: the wire
values/schema, the request/response protocol, framing, the pairing/session
cryptography, and the credential store — everything both the device runtime and
the Mac surfaces must agree on. See [`README.md`](README.md) for the full type
tour and the pairing handshake spec.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + CryptoKit + Security only.** No UI, no `Network`, no logging
  stack. It must compile for **iOS and macOS** (every Mac surface links it), so
  never reach for a UIKit/iOS-only API here — platform-specific code lives in
  `PortholeKit` (device) or `PortholeClientKit` (Mac).
- Nothing in the suite may duplicate these types; connectors and both runtimes
  depend on this module for them.

## Invariants

- **`PortholeValue` is the only thing that crosses the wire.** Its `.data` /
  `.date` tagged encodings (`{"$data":…}` / `{"$date":…}`) are the reason binary
  and timestamps survive a JSON round-trip — keep the hand-written `Codable`
  (documented on the conformance; it is exception (a), the single-value wire
  shape). Everything else prefers synthesized `Codable`.
- **The device validates parameters against `PortholeSchema` before invoking a
  handler.** `jsonSchema()` and `validate(_:)` derive from the *same* schema, so
  the MCP tool contract and the runtime check can't drift.
- **Framing caps every frame at 32 MiB** (`PortholeFraming`); a larger declared
  length throws rather than allocating. `PortholeFramer` tolerates arbitrary
  chunking — one per connection/direction, not thread-safe.
- **Security is application-layer, deterministic, and loopback-testable.**
  Pairing derives the PSK from X25519 + HKDF over the 6-digit code;
  `PortholeSecureChannel` seals frames with ChaCha20-Poly1305 under a
  counter-derived, never-transmitted nonce, so replay/reorder/tamper all fail to
  open. The 6-digit code's MITM limitation is documented in the README — don't
  quietly "fix" it with a weaker scheme.
- **Credentials never fail silently.** `PortholeCredentialStore` throws on
  keychain errors (a swallowed failure would read as "not paired").

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeCoreTests`). Prefer exercising the real stack over `LoopbackTransport`
to network mocks; pairing/session tests inject a seeded RNG and never sleep.
