# PortholeCLICore

PortholeCLICore holds all of the `porthole` command-line tool's logic. The
executable target (`PortholeCLI`, a Tuist `.commandLineTool`) is a one-line
`main.swift` that calls `PortholeCommand.main()`; everything testable lives here.

Built on `swift-argument-parser` over `PortholeClientKit`.

## Commands

- `porthole devices [--timeout N]` — list discovered + paired apps.
- `porthole pair [--app <sel>] [--timeout N]` — discover and pair (prompts for
  the code shown on the device).
- `porthole unpair [--app <sel>]` — forget a pairing locally.
- `porthole connectors [--app <sel>]` — table of the app's connectors.
- `porthole actions [<connector>] [--app <sel>]` — actions + parameter schemas.
- `porthole sources [<connector>] [--app <sel>]` — data sources + filter schemas.
- `porthole call <connector>/<action> [--param k=v ...] [--json '<obj>'] [--yes] [--out <path>]`
  — invoke an action; destructive actions confirm unless `--yes`; a returned data
  value writes to `--out` instead of printing base64.
- `porthole query <connector>/<source> [--filter k=v ...] [--limit N] [--cursor C] [--all] [--format table|json]`
  — page through a data source.
- `porthole tail <connector>/<source> [--filter k=v ...]` — stream a subscribable
  source until interrupted.
- `porthole mcp [--app <sel>]` — serve the app as an MCP server over stdio (added
  with PortholeMCP).

`--app` is optional when exactly one app is paired; otherwise pass a bundle id or
an app/device-name substring that uniquely matches.

`--param`/`--filter` values infer type: `true`/`false` → bool, integers → int,
decimals → double, everything else → string. Use `--json` for full control.

## Permissions

The first run prompts for macOS local-network access (Bonjour). Credentials are
shared with the app and MCP via the login keychain (see
[PortholeClientKit](../PortholeClientKit/README.md)).

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeCLICoreTests`). The pure logic — ref/param/JSON parsing, table and JSON
formatting, and `--app` resolution — is covered without a device; the
device-talking commands are thin glue over `PortholeClientKit`.
