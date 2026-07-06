// End-to-end test of the tools against a *mock* Foreman control socket and a
// real temp git repo — no Foreman app or Cursor session required. Verifies the
// git side actually happens on disk and that the right control requests are
// sent. Run with `npm test` after `npm run build`.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, rmSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const serverEntry = path.join(here, "..", "dist", "index.js");

function assert(condition, msg) {
  if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function textOf(result) {
  return (result.content ?? [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
}

const tmp = mkdtempSync(path.join(tmpdir(), "foreman-mcp-it-"));
const scanDir = path.join(tmp, "Development");
mkdirSync(scanDir, { recursive: true });
const source = path.join(scanDir, "Main");
const socketPath = path.join(tmp, "control.sock");

// A real git repo with one commit so `worktree add` works.
const git = (args, cwd) => execFileSync("/usr/bin/git", args, { cwd, stdio: "ignore" });
mkdirSync(source, { recursive: true });
git(["init", "-q"], source);
git(["config", "user.email", "t@example.com"], source);
git(["config", "user.name", "Test"], source);
execFileSync("/bin/sh", ["-c", "echo hi > README.md"], { cwd: source });
git(["add", "."], source);
git(["commit", "-q", "-m", "init"], source);

// Mock Foreman: records requests and returns plausible responses.
const received = [];
const mock = net.createServer((socket) => {
  let buffer = "";
  socket.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    const nl = buffer.indexOf("\n");
    if (nl < 0) return;
    const request = JSON.parse(buffer.slice(0, nl));
    received.push(request);
    let response;
    if (request.command === "describe") {
      response = {
        ok: true,
        kind: "describe",
        describe: {
          scanDirectory: scanDir,
          repos: [
            {
              id: source,
              name: "Main",
              path: source,
              enabled: false,
              workerState: "stopped",
            },
          ],
        },
      };
    } else if (request.command === "adopt") {
      response = {
        ok: true,
        kind: "repo",
        repo: {
          id: request.path,
          name: path.basename(request.path),
          path: request.path,
          enabled: true,
          workerState: "running",
          pid: 4242,
          provenance: request.provenance,
        },
      };
    } else if (request.command === "removeCopy") {
      response = { ok: true, kind: "removed", path: request.path };
    } else {
      response = { ok: false, error: `unknown command ${request.command}` };
    }
    socket.end(`${JSON.stringify(response)}\n`);
  });
});

async function run() {
  await new Promise((resolve) => mock.listen(socketPath, resolve));

  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [serverEntry],
    env: { ...process.env, FOREMAN_CONTROL_SOCKET: socketPath },
  });
  const client = new Client({ name: "foreman-mcp-it", version: "0.0.0" });
  await client.connect(transport);

  // 1. Spin up a worktree.
  const spinup = await client.callTool({
    name: "spinup_repo_copy",
    arguments: { mode: "worktree", sourceRepo: source, name: "Main-copy", branch: "task" },
  });
  const spinupText = textOf(spinup);
  console.error(`spinup_repo_copy -> ${spinupText}`);
  assert(!spinup.isError, "spinup did not error");
  const copyPath = path.join(scanDir, "Main-copy");
  assert(existsSync(path.join(copyPath, ".git")), "worktree .git exists on disk");
  assert(spinupText.includes("running"), "worker reported running");

  const adoptReq = received.find((r) => r.command === "adopt");
  assert(adoptReq, "an adopt request was sent");
  assert(adoptReq.path === copyPath, `adopt path is the copy (${adoptReq.path})`);
  assert(adoptReq.provenance.kind === "worktree", "adopt provenance kind is worktree");
  assert(adoptReq.provenance.branch === "task", "adopt provenance branch is task");
  assert(adoptReq.provenance.parentRepoID.endsWith("/Main"), "adopt parent is Main");

  // Worktree really is on the requested branch.
  const branch = execFileSync("/usr/bin/git", ["-C", copyPath, "branch", "--show-current"])
    .toString()
    .trim();
  assert(branch === "task", `worktree is on branch task (got ${branch})`);

  // 2. List repos.
  const list = await client.callTool({ name: "list_repos", arguments: {} });
  const listText = textOf(list);
  console.error(`list_repos ->\n${listText}`);
  assert(listText.includes("Main"), "list includes Main");

  // 3. Remove the copy.
  const remove = await client.callTool({
    name: "remove_repo_copy",
    arguments: { path: copyPath },
  });
  const removeText = textOf(remove);
  console.error(`remove_repo_copy -> ${removeText}`);
  assert(!remove.isError, "remove did not error");
  const removeReq = received.find((r) => r.command === "removeCopy");
  assert(removeReq && removeReq.path === copyPath, "removeCopy sent for the copy path");

  await client.close();
  console.error("INTEGRATION OK");
}

let exitCode = 0;
try {
  await run();
} catch (error) {
  console.error("INTEGRATION FAILED:", error);
  exitCode = 1;
} finally {
  mock.close();
  rmSync(tmp, { recursive: true, force: true });
  process.exit(exitCode);
}
