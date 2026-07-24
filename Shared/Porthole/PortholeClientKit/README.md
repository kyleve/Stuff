# PortholeClientKit

PortholeClientKit is the Mac-side client of the [Porthole](../) suite: discover
device apps over Bonjour, pair with them, and open authenticated sessions to
invoke actions, query data sources, and tail live streams. It is pure
Foundation + Network + CryptoKit (via PortholeCore), so the same framework backs
the CLI, the MCP server, and the Catalyst app.

## Using it

```swift
// Discover
for await apps in PortholeBrowser().discovered() { /* show apps */ }

// Pair (persists the credential in the shared login keychain)
let paired = try await PortholePairingClient().pair(with: app) {
    await promptUserForCode()          // read the code shown on the device
}

// Connect and use
let session = try await PortholeClient().connect(to: paired)
let manifests = try await session.manifest()
let result = try await session.invoke(.init(connector: "app", action: "ping"),
                                      parameters: ["message": "hi"])
for try await event in try await session.subscribe(.init(connector: "periscope", source: "live-events")) {
    print(event)
}
```

Credentials live in the login keychain under
`com.stuff.porthole.client`, so pairing once from any surface (CLI, app, MCP)
works for all of them.

### Keychain prompt caveat

macOS login-keychain items carry per-application ACLs. The first time a
*different* Mac surface reads a PSK another created, macOS shows a
keychain-access prompt — click **Always Allow**. The `PairedApp` metadata is
plain shared state and needs no prompt. This is acceptable for a developer tool
and isn't worked around in v1.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeClientKitTests`). The marquee suite runs the *real* device
(PortholeKit) and client stacks in one process over a `LoopbackTransport`: it
pairs, opens an encrypted session, and exercises invoke/query/subscribe through
the secure channel, plus wrong-code and revoked-pairing rejection. The
`@_spi(Testing)` `connect(over:)` / `pair(over:)` seams bypass Bonjour so no
networking is involved.
