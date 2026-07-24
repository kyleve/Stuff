# Porthole

Porthole gives local agents (and humans) access to the data and operations
inside a **running iOS app** from a Mac — over a paired Bonjour/TCP bridge —
through an MCP server, a command-line tool, and a Mac app. App developers expose
surfaces by registering **connectors** (actions + data sources); built-in
connectors cover app info, the view/accessibility hierarchy + screenshots, the
file system, notifications, permissions, Periscope logs, SwiftData stores, and
LifecycleKit launch state. The Where app adds a domain-specific `WhereConnector`.

## Modules

Device side (embedded in the iOS app):

- **[PortholeCore](PortholeCore)** — shared wire protocol, values/schema,
  framing, pairing/session crypto, transports. iOS + macOS.
- **[PortholeKit](PortholeKit)** — the device runtime: `Porthole` composition
  root, the `PortholeConnector` protocol, the Bonjour listener + secure sessions,
  and the built-in `app` / `ui` / `files` / `notifications` / `permissions`
  connectors.
- **[PortholeKitUI](PortholeKitUI)** — the Broadway-styled `PortholePairingView`.
- **[PortholePeriscope](PortholePeriscope)** / **[PortholeSwiftData](PortholeSwiftData)**
  / **[PortholeLifecycle](PortholeLifecycle)** — library connectors over the
  respective frameworks. (`WherePorthole` lives under `Where/`.)

Mac side:

- **[PortholeClientKit](PortholeClientKit)** — discovery, pairing, and
  authenticated sessions. Backs all three surfaces.
- **[PortholeMCP](PortholeMCP)** — maps a session to an MCP stdio server.
- **[PortholeCLICore](PortholeCLICore)** — the `porthole` CLI logic (the
  `PortholeCLI` executable is a thin `@main`).
- **PortholeApp** — the Mac Catalyst client app (`Porthole`).

## How it fits together

```
iOS app: Porthole(configuration:) + register(connectors) + start()
             │  advertises _porthole._tcp, accepts paired, encrypted sessions
             ▼
Mac: PortholeClientKit  ──►  porthole CLI  /  porthole mcp (MCP)  /  Porthole.app
```

Pairing is a one-time 6-digit code exchange; credentials live in the login
keychain, shared across all Mac surfaces. Everything ships in release but is
inert until the app calls `start()` (Where gates it behind a `#if DEBUG`
developer-menu toggle).

## Security & scope

Porthole is a **developer tool for a trusted LAN**. The pairing code doesn't
resist an active MITM (see [PortholeCore](PortholeCore/README.md#known-limitation));
a SPAKE2 upgrade and other follow-ups are in [TODOs.md](TODOs.md).

## Building

The Mac targets are macOS-only (see the root
[`AGENTS.md`](../../AGENTS.md)): `mise exec -- tuist build PortholeCLI` and
`mise exec -- tuist build PortholeApp -- -destination 'platform=macOS,variant=Mac Catalyst'`.
The library logic is tested in the iOS `Stuff-iOS-Tests` scheme; CI builds the
Mac targets in a separate `macos` job.
