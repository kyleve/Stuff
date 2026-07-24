# Porthole – Roadmap / Deferred

Tracked follow-ups for the [Porthole](README.md) suite. These were deliberately
left out of v1; each notes why and roughly what it entails.

## Transport & hosting

- **Mac daemon / menubar host with a persistent HTTP MCP endpoint.** v1 has no
  always-on Mac process: each surface (CLI, MCP, app) links `PortholeClientKit`
  and connects directly, and the MCP is a stdio subprocess. A menubar app +
  launchd daemon hosting a shared, always-on HTTP MCP endpoint would give
  always-available access and connection sharing across surfaces. The client and
  wire protocol already support concurrent sessions, so this is additive.
- **SPAKE2 pairing.** The 6-digit code is a usability/security trade-off for a
  LAN dev tool and doesn't resist an active MITM grinding the code offline
  during the exchange (documented in `PortholeCore/README.md`). A SPAKE2 (or
  similar PAKE) upgrade would close that gap. It's a `PortholeCore` change behind
  the same `PortholePairingMessage` shape.

## Connectors

- **Screenshot beyond a single window / device screen capture.** The `ui`
  connector renders one window; full-device or scene-composited capture is more.
- **Write-capable file operations.** `files` is read-only in v1; write/delete
  would need careful guarding (and probably an explicit opt-in per host app).
- **Write-capable preferences / store mutation for Where.** `WhereConnector` is
  read-mostly with no destructive actions. Editing preferences, or mutating the
  store (manual-day edits, reset), needs destructive-action UX and care.
- **Evidence / backup blob transfer.** `WhereConnector.evidence` returns
  metadata only, and there's no `export-backup` action, because moving large
  binary blobs over the wire needs a streaming/chunked story (the frame cap is
  32 MiB). Design a blob-transfer path, then add `export-backup` + evidence
  bytes.
- **Lifecycle retry / teardown actions.** `PortholeLifecycle` is read-only
  (`launch-state`); exposing `retry()` / `teardown()` as actions would let an
  agent drive relaunch, but they're destructive and need care.
- **App Intents bridge connector.** Enumerate and invoke an app's App Intents
  through Porthole. Heavier (intent parameter resolution, entities), so deferred.

## Tooling

- **AI connector-builder in the Mac app.** With a user-entered API key
  (Cursor / Anthropic / OpenAI), a prompt scaffold that feeds a target module's
  source plus the connector protocol/spec to a model to draft a new connector.

## UI / platform

- **Embed the client UI in an iOS app** (e.g. run the browser on-device for
  debugging), and a first-class **iPad build** of the Porthole app (Catalyst
  already keeps this plausible).
