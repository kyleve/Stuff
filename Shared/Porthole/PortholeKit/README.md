# PortholeKit

PortholeKit is the device-side runtime of the [Porthole](../) suite — the
framework an iOS app embeds to expose its data and operations to a paired Mac.
An app creates one `Porthole`, registers connectors, and calls `start()`; the
runtime advertises over Bonjour, runs the pairing/session handshake, and routes
requests to the connectors.

## Using it

```swift
let porthole = Porthole(configuration: .init(appName: "Where"))
porthole.register(WhereConnector(services: services))
try porthole.start()          // advertises + accepts connections
// porthole.state drives the pairing UI (see PortholeKitUI)
```

`Porthole` is `@MainActor` + `@Observable`; bind UI to `porthole.state`
(`isAdvertising`, `pendingPairingCode`, `pairedHosts`, `activeSessionCount`).
The built-in `app` connector (app/device info + `ping`) is registered
automatically.

## Writing a connector

Conform to `PortholeConnector` and return `PortholeAction`s and
`PortholeDataSource`s. Each action has a `PortholeSchema` for its parameters
(validated by the runtime before your handler runs) and an `isDestructive`
flag; each data source has a paginated `fetch` and, optionally, a `subscribe`
that vends a live `AsyncStream` of rows.

## Host app requirements

Advertising needs no user prompt. A host app should still declare, in its
Info.plist, that it uses Bonjour if it also *browses* (it normally doesn't):

- `NSBonjourServices` = `["_porthole._tcp"]`
- `NSLocalNetworkUsageDescription` = a short reason string

Gate `start()` behind `#if DEBUG` (or a developer toggle) — Porthole ships in
release inert, but you rarely want it advertising in a shipping build.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeKitTests`). The `@_spi(Testing)` `Porthole.attach(transport:)` seam
serves a full session over a `LoopbackTransport`, so the request router,
schema validation, dispatch, and subscription streaming are all exercised
in-process with no networking. The network layer (`PortholeServer`,
`NWConnectionTransport`) is deliberately thin over that tested core.
