# PortholeApp – Module Shape

PortholeApp is the Porthole Mac client app (SwiftUI, Mac Catalyst, product name
`Porthole`): sidebar of paired/discovered apps, connector browser, paged
data-source table with a live tail toggle, and a schema-generated action form.
See [`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- A **Tuist app target** (in `Project.swift`), not an SPM library. Depends on
  `PortholeClientKit` (discovery/pairing/sessions) + `BroadwayCore`/`BroadwayUI`.
- **Unsandboxed by design** — a dev tool that shares the login keychain +
  Application Support metadata with the CLI and MCP. Don't add an App Sandbox
  entitlement.
- Info.plist declares `NSLocalNetworkUsageDescription` + `NSBonjourServices`
  (`_porthole._tcp`) so it can browse and connect.

## Invariants

- **Keep logic in `@Observable` models** (`AppModel`, `SourceTableModel`,
  `ActionFormModel`); views render and route. The models orchestrate
  `PortholeClientKit` — they don't reimplement protocol logic.
- **A live tail is torn down on view disappearance** (`SourceTableModel.teardown`
  from `.onDisappear`) since a Swift 6 `deinit` can't touch main-actor state;
  every start has a stop.
- **Pairing awaits the user's code** via a continuation the sheet resumes — the
  device shows the code, the user types it, the pairing client consumes it.

## Testing

No unit-test bundle: the model logic is thin over `PortholeClientKit` (which is
end-to-end tested). CI builds this target for Mac Catalyst (`macos` job).
