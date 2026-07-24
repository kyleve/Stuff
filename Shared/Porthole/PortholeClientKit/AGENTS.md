# PortholeClientKit – Module Shape

PortholeClientKit is the Mac-side Porthole client: `PortholeBrowser` (Bonjour
discovery), `PortholePairingClient` (pairing + credential persistence),
`PortholeClient` (open a session to a paired app), and the `PortholeSession`
actor (request/response + subscription streams). See [`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- Depends only on **PortholeCore** (+ `Network`/`Security`/`CryptoKit` from the
  SDK). It must **not** depend on PortholeKit (the device runtime) — the two
  sides meet only over the wire. Compiles for macOS *and* iOS/Catalyst; the CLI,
  MCP server, and app all link it.
- Credentials use the shared login keychain under
  `com.stuff.porthole.client` (`PortholeCredentialService.client`), so a pairing
  made by one surface is visible to the others. `PairedApp` is the metadata blob;
  the PSK sits beside it.

## Invariants

- **The client handshake mirrors the device's** (`ClientHandshake`): X25519 +
  HKDF over the code for pairing, HKDF over the nonces for the session key. It's
  pure of `Network` types so it runs over `LoopbackTransport` in tests.
- **`PortholeSession` matches responses to requests by id** and routes
  unsolicited `.event` frames to the subscription stream that requested them; a
  `.failure` response throws the carried `PortholeError`. Cancelling a
  subscription stream unsubscribes on the device (every start has a stop).
- **Connecting re-derives a fresh session key** and verifies protocol version in
  the app-level hello before returning the session.
- **Discovery/connection Network code is thin**; the tested logic is the
  handshake + session, exercised end-to-end against the real device stack over
  loopback via the `@_spi(Testing)` `connect(over:)` / `pair(over:)` seams.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeClientKitTests`, `extraPackageProducts: [PortholeCore, PortholeKit]`).
The `DeviceHarness` drives the real device side over loopback; tests wait on
delivered events and never sleep.
