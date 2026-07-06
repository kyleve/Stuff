// Smoke test: launches the built server over stdio and exercises the MCP
// handshake end to end (initialize -> tools/list -> tools/call). Run with
// `npm run smoke` after `npm run build`. Exits non-zero on any failure so it
// can gate CI.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const serverEntry = join(here, "..", "dist", "index.js");

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion failed: ${message}`);
  }
}

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [serverEntry],
});
const client = new Client({ name: "foreman-mcp-smoke", version: "0.0.0" });

try {
  await client.connect(transport);

  const { tools } = await client.listTools();
  const names = tools.map((t) => t.name);
  console.error(`tools/list -> ${names.join(", ")}`);
  assert(names.includes("foreman_ping"), "foreman_ping tool is listed");

  const result = await client.callTool({
    name: "foreman_ping",
    arguments: { message: "smoke" },
  });
  const text = (result.content ?? [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
  console.error(`foreman_ping -> ${text}`);
  assert(text.includes("pong"), "foreman_ping returns pong");

  console.error("SMOKE OK");
  await client.close();
  process.exit(0);
} catch (error) {
  console.error("SMOKE FAILED:", error);
  try {
    await client.close();
  } catch {
    // ignore
  }
  process.exit(1);
}
