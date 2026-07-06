# foreman-mcp – Module Shape

A Node/TypeScript **stdio MCP server** that lets a Cursor agent spin up
worktree/clone copies of a repo and hand them to [Foreman](../Foreman) to run a
worker on — see [`README.md`](README.md) for the tools, the flow, and how to
register it. This is the only non-Swift module in the repo.

This file complements the root [`AGENTS.md`](../../AGENTS.md) (build/format/global
rules) and the Foreman docs it talks to
([ForemanCore](../ForemanCore/AGENTS.md), [app](../Foreman/AGENTS.md)). Read
those first.

## Scope & dependencies

- Runtime deps are only `@modelcontextprotocol/sdk` + `zod`; git runs via
  `node:child_process`. No dependency on the Swift code at build time — the only
  coupling is the **wire protocol**.
- Not part of the Tuist/Swift build. Build with `npm run build` (→ `dist/`),
  test with `npm test`. `dist/` and `node_modules/` are gitignored; the
  committed source of truth is `src/` + `test/`.
- Boundary: this server owns **creation git** (worktree/clone). Foreman owns
  **worker lifecycle and copy removal** — don't add worker-spawning or
  filesystem-removal here; call the control socket instead.

## Layering

- [`src/index.ts`](src/index.ts) — the MCP surface: tool registration, arg
  validation (`zod`), and orchestration. [`src/git.ts`](src/git.ts) — git
  `execFile` helpers. [`src/control.ts`](src/control.ts) — the socket client.
  Keep git and control concerns in their files; `index.ts` composes them.

## Invariants

- **stdout is reserved for JSON-RPC.** All logging goes to stderr (`log()`).
  Never `console.log` / write to stdout.
- **The wire types in `src/control.ts` mirror
  `ForemanCore/Sources/ControlProtocol.swift`.** Change one side and you must
  change the other — the socket is JSON-lines (one request line, one response
  line) with no versioning.
- **Foreman-down is a normal path, not an error.** A missing/refused socket or
  timeout is `ForemanUnavailableError`; `spinup_repo_copy` still reports the git
  copy it made and says no worker started. Never report a silent success or a
  hard failure for a copy that was actually created.
- **Errors are never swallowed.** git failures surface as `GitError` with
  stderr; control failures as `ForemanError`/`ForemanUnavailableError`.

## Testing

`npm test` runs [`test/smoke.mjs`](test/smoke.mjs) (ping over stdio) and
[`test/integration.mjs`](test/integration.mjs) (end-to-end against a mock unix
socket + a real temp git repo — never the user's `~/Development`).
[`test/describe-live.mjs`](test/describe-live.mjs) is a manual helper that talks
to a live Foreman socket.
