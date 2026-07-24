# PortholeMCP – Module Shape

PortholeMCP maps a `PortholeSession` to an MCP stdio server: `MCPToolBuilder`
plans the tools from a manifest, `PortholeMCPDispatcher` routes calls to the
session, and `PortholeMCPServer` wires both to the official MCP Swift SDK. See
[`README.md`](README.md) for the tool surface.

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- Depends on **PortholeClientKit** and the external **MCP** product. It talks to
  the device only through the `PortholeSessionProviding` seam (which
  `PortholeSession` conforms to), so the tool logic is testable against a fake.
- MCP SDK types stay quarantined: only `MCPValueBridge` and `PortholeMCPServer`
  import `MCP`. The planner and dispatcher are pure of SDK types (they speak
  `PortholeValue` / `MCPCallResult`), which is what makes them unit-testable.

## Invariants

- **Tool names are sanitized** (`[a-z0-9_]`, lowercased) and namespaced:
  `act_/query_/tail_<connector>_<member>`, plus `porthole_overview`. The
  name → target map drives dispatch.
- **Tail is bounded** (duration ≤ 60 s, events ≤ 500) since MCP tools are
  request/response; a PNG action result is returned as image content, other
  results as JSON text, and a session error becomes an `isError` result — never
  a crash.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeMCPTests`, `extraPackageProducts: [PortholeClientKit, PortholeCore]`).
Drive the planner and dispatcher against `FakeSession`; no real MCP transport.
