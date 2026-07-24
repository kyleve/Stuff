# PortholeMCP

PortholeMCP exposes a connected Porthole session as a
[Model Context Protocol](https://modelcontextprotocol.io) server over stdio, so
an agent (Cursor, Claude, …) can drive a running iOS app. It's built on the
official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) over
`PortholeClientKit`, and is what `porthole mcp` runs.

## Tools

From the device manifest it generates:

- `porthole_overview` — the whole manifest (connectors, actions, sources,
  schemas) as JSON. An agent's entry point.
- `act_<connector>_<action>` — invoke an action; input is the action's parameter
  schema. A returned PNG (a screenshot) comes back as MCP **image** content;
  other results are JSON text. Destructive actions say so in their description.
- `query_<connector>_<source>` — a page of rows; input is the source's filters
  plus `limit` and `cursor`.
- `tail_<connector>_<source>` — for subscribable sources; collects live events
  for a bounded window (`durationSeconds` ≤ 60, `maxEvents` ≤ 500) and returns
  them as an array (MCP tools are request/response).

## Using it

```swift
let session = try await PortholeClient().connect(to: pairedApp)
try await PortholeMCPServer(session: session, serverName: "porthole-Where").run()
```

Or, from the CLI, register `porthole mcp --app <name>` as an MCP server in your
agent.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeMCPTests`). Tool planning (`MCPToolBuilder`) and call dispatch
(`PortholeMCPDispatcher`) are tested against a scripted `PortholeSessionProviding`
fake — no MCP client and no device — covering naming/sanitization, targets,
invoke/query/tail dispatch, PNG-to-image detection, and error mapping.
