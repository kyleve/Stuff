# PortholeApp

PortholeApp is the Porthole Mac client — a SwiftUI app (Mac Catalyst, built
product named **Porthole**) for browsing and driving paired iOS apps, alongside
the CLI and MCP server. It's a Tuist app target (see
[`Project.swift`](../../../Project.swift)), not an SPM library.

## What it does

- **Sidebar** — paired apps (swipe to unpair) and live-discovered apps with a
  **Pair** button. Pairing prompts for the 6-digit code the device shows.
- **Connector browser** — the selected app's connectors, each listing its data
  sources and actions.
- **Data-source table** — a paged table (Load More) with a **Live** toggle for
  subscribable sources that appends streamed events.
- **Action form** — a form generated from the action's parameter schema (with a
  raw-JSON editor fallback), showing the JSON result.

Built on [`PortholeClientKit`](../PortholeClientKit) for discovery, pairing, and
sessions, and [Broadway](../../Broadway) for styling. Credentials are shared with
the CLI and MCP via the login keychain.

## Not sandboxed

It's a developer tool, so it ships without the App Sandbox — that's what lets it
share the login keychain and `~/Library/Application Support/Porthole/` metadata
with the CLI and MCP server, and use the local network freely.

## Testing

App model/view logic is intentionally thin over `PortholeClientKit` (which is
end-to-end tested against the real device stack). CI builds this target for Mac
Catalyst (the `macos` job in [`ci.yml`](../../../.github/workflows/ci.yml)); it
has no separate unit-test bundle.
