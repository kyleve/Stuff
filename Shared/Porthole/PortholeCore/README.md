# PortholeCore

PortholeCore is the shared foundation of the [Porthole](../) suite — the types
and protocol that both ends of the bridge speak. It has no UI and no
networking; it is pure Foundation + CryptoKit and compiles for iOS and macOS,
so the device runtime (`PortholeKit`) and every Mac surface (`PortholeClientKit`,
the CLI, the MCP server, the app) build against exactly the same wire contract.

## What's in here

- **`PortholeValue`** — the single data currency. A JSON-shaped tree with two
  extensions over plain JSON, `.data` and `.date`, that round-trip binary and
  timestamps unambiguously (tagged as `{"$data": …}` / `{"$date": …}`).
- **`PortholeSchema`** — a small JSON-Schema subset describing action
  parameters and data-source rows/filters. It renders to a JSON-Schema object
  (`jsonSchema()`, feeds an MCP tool's `inputSchema`) and validates values at
  runtime (`validate(_:)`, applied on the device before a handler runs).
- **Identifiers & descriptors** — typed `PortholeConnectorID` /
  `PortholeActionID` / `PortholeDataSourceID`, their refs, and the
  `ConnectorManifest` that advertises a connector's surface.
- **Query & page** — `PortholeQuery` (filters + limit + opaque cursor) and
  `PortholePage` (rows + `nextCursor`).
- **Wire protocol** — `PortholeRequest` / `PortholeResponse` and their
  envelopes, `PortholeError`, and `portholeProtocolVersion`.
- **Framing & transport** — `PortholeFraming` / `PortholeFramer` (4-byte
  big-endian length prefix, 32 MiB cap), the `PortholeTransport` protocol, and
  the in-memory `LoopbackTransport` test seam.
- **Pairing & session security** — `PortholePairingMessage`,
  `PairingCryptography` (X25519 + HKDF-SHA256 + HMAC), and
  `PortholeSecureChannel` (ChaCha20-Poly1305 record layer).
- **Credentials** — `PortholeCredentialStore` with a Keychain-backed
  implementation (`KeychainCredentialStore`) shared by both sides under
  different service strings.

## The pairing & session handshake

All messages are length-prefixed frames. Pairing frames are **plaintext**
(`PortholePairingMessage`); once a session key exists, every frame is sealed by
`PortholeSecureChannel`. The client is the Mac, the device is the iOS app.

**Pairing** (establishes a long-term PSK):

1. Client → `clientHello(.pair(clientName, clientPublicKey))`.
2. Device shows a fresh 6-digit code, and replies
   `pairChallenge(devicePublicKey, salt)`.
3. Both compute `psk = HKDF-SHA256(X25519(shared), salt, info:
   "porthole-pair-v1|" + code)`.
4. Client → `pairConfirm(mac = HMAC(psk, clientPub ‖ devicePub ‖ salt))`.
   Device verifies; wrong code fails, and after 3 attempts the code is burned.
5. Device mints a `pairingID`, stores `(pairingID, psk)`, and replies
   `pairAccepted(pairingID, mac = HMAC(psk, salt ‖ clientPub))` (mutual proof).
   Both persist the credential; the connection then closes.

**Session** (per connection, re-derives a fresh record key):

1. Client → `clientHello(.session(pairingID, clientNonce))`.
2. Device looks up the PSK (unknown → `notPaired`) and replies
   `serverHello(serverNonce)`.
3. Both derive `sessionKey = HKDF-SHA256(psk, salt: clientNonce ‖ serverNonce,
   info: "porthole-session-v1")`. Every later frame is
   `ChaChaPoly.seal(…, nonce: directionTag ‖ counter)` — the nonce is derived,
   never sent, so any reorder/replay/tamper fails to open and closes the
   connection.

### Known limitation

The 6-digit code is a usability/security trade-off for a **LAN developer tool**:
it does not resist an active man-in-the-middle who can grind the code offline
during steps 3–4. A SPAKE2 upgrade is on the [roadmap](../TODOs.md). Do not use
Porthole to expose sensitive production data over untrusted networks.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeCoreTests`). The whole stack — framing, the pairing crypto, and the
secure channel — is exercised in-process over `LoopbackTransport`, so there is
no networking in the test path.
