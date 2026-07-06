#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { existsSync } from "node:fs";
import path from "node:path";
import { z } from "zod";
import {
  adopt,
  type CopyProvenanceWire,
  describe,
  ForemanUnavailableError,
  removeCopy,
} from "./control.js";
import {
  addWorktree,
  checkoutBranch,
  cloneRepo,
  isGitRepo,
  originURL,
  repoToplevel,
  setOriginURL,
} from "./git.js";

// stdio transport: stdout carries the JSON-RPC protocol, so all diagnostics go
// to stderr only.
function log(message: string): void {
  process.stderr.write(`[foreman-mcp] ${message}\n`);
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

type TextResult = {
  content: { type: "text"; text: string }[];
  isError?: boolean;
};

function ok(text: string): TextResult {
  return { content: [{ type: "text", text }] };
}

function fail(text: string): TextResult {
  return { content: [{ type: "text", text }], isError: true };
}

/// A caller-supplied copy name must be a single, visible directory segment: no
/// path separators (which would escape the scan dir), no NUL, and no leading
/// dot (`.`/`..` escape, and a hidden dir is skipped by Foreman's discovery so
/// the copy could never be adopted). Defaults derived from the repo name are
/// always safe, so only an explicit `name` is checked.
function isValidCopyName(name: string): boolean {
  return (
    name.length > 0 &&
    !name.startsWith(".") &&
    !name.includes("/") &&
    !name.includes("\\") &&
    !name.includes("\0")
  );
}

/// Turns arbitrary text into a safe single directory-name segment.
function slug(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
}

function shortId(): string {
  return Date.now().toString(36).slice(-6);
}

/// Picks a destination path that doesn't collide, auto-suffixing `-2`, `-3`, …
function uniqueDestination(scanDir: string, name: string): string {
  let candidate = path.join(scanDir, name);
  let suffix = 2;
  while (existsSync(candidate)) {
    candidate = path.join(scanDir, `${name}-${suffix}`);
    suffix += 1;
  }
  return candidate;
}

const server = new McpServer({ name: "foreman-mcp", version: "0.1.0" });

server.registerTool(
  "foreman_ping",
  {
    title: "Foreman ping",
    description:
      "Health check for the Foreman MCP server. Returns 'pong' so you can confirm the server is reachable from this session.",
    inputSchema: { message: z.string().optional() },
  },
  async ({ message: text }) => ok(`pong${text ? `: ${text}` : ""}`),
);

server.registerTool(
  "spinup_repo_copy",
  {
    title: "Spin up a repo copy",
    description:
      "Create another working copy of a git repository — a lightweight `git worktree` or a full `git clone` — as a sibling directory under Foreman's scan directory, and (by default) have Foreman start a cursor-agent worker on it so it's immediately available for a new task. Pass `sourceRepo` as the absolute path of the repo you're working in.",
    inputSchema: {
      mode: z
        .enum(["worktree", "clone"])
        .describe(
          "worktree = fast, shares the object store, one branch per copy; clone = a fully independent copy.",
        ),
      sourceRepo: z
        .string()
        .optional()
        .describe("Absolute path to the source repo (defaults to the server's working directory)."),
      name: z
        .string()
        .optional()
        .describe("Directory name for the copy (defaults to '<repo>-<branch|id>')."),
      branch: z
        .string()
        .optional()
        .describe("Branch to check out in the copy (defaults to 'foreman/<name>')."),
      baseRef: z
        .string()
        .optional()
        .describe("Ref the new branch starts from (defaults to the source's current HEAD)."),
      enable: z
        .boolean()
        .default(true)
        .describe("Whether Foreman should start a worker on the copy."),
    },
  },
  async ({ mode, sourceRepo, name, branch, baseRef, enable }) => {
    const source = path.resolve(sourceRepo ?? process.cwd());
    if (!(await isGitRepo(source))) {
      return fail(
        `'${source}' isn't a git repository. Pass 'sourceRepo' as the absolute path of the repo you're working in.`,
      );
    }
    if (name !== undefined && !isValidCopyName(name)) {
      return fail(
        `'name' must be a single visible directory name — no '/', no leading dot, not '.'/'..' (got '${name}').`,
      );
    }

    let sourceTop: string;
    try {
      sourceTop = await repoToplevel(source);
    } catch (error) {
      return fail(`Couldn't resolve the repo root of '${source}': ${message(error)}`);
    }

    // Prefer Foreman's own scan directory so the copy is discovered; fall back
    // to the source's parent when Foreman isn't running.
    let scanDir: string;
    let foremanReachable = true;
    try {
      scanDir = (await describe()).scanDirectory;
    } catch (error) {
      if (error instanceof ForemanUnavailableError) {
        foremanReachable = false;
        scanDir = path.dirname(sourceTop);
      } else {
        return fail(`Couldn't query Foreman: ${message(error)}`);
      }
    }

    const baseName = path.basename(sourceTop);
    const resolvedName = name ?? `${baseName}-${branch ? slug(branch) : shortId()}`;
    const resolvedBranch = branch ?? `foreman/${slug(resolvedName)}`;
    const dest = uniqueDestination(scanDir, resolvedName);

    try {
      if (mode === "worktree") {
        await addWorktree(sourceTop, dest, resolvedBranch, baseRef);
      } else {
        await cloneRepo(sourceTop, dest);
        await checkoutBranch(dest, resolvedBranch, baseRef);
        // The clone's origin points at the local source; repoint it at the
        // source's own upstream when there is one, so it isn't a dead local
        // path.
        const upstream = await originURL(sourceTop);
        if (upstream) await setOriginURL(dest, upstream);
      }
    } catch (error) {
      return fail(`Couldn't create the ${mode}: ${message(error)}`);
    }

    log(`Created ${mode} at ${dest} on branch ${resolvedBranch}`);
    const created = `Created a ${mode} at ${dest} on branch '${resolvedBranch}'`;
    const provenance: CopyProvenanceWire = {
      kind: mode,
      parentRepoID: sourceTop,
      branch: resolvedBranch,
    };

    if (!enable) {
      return ok(`${created}. Worker not started (enable=false).`);
    }
    if (!foremanReachable) {
      return ok(
        `${created}, but Foreman isn't running, so no worker was started. Launch Foreman (or enable this repo in it) to run a worker here.`,
      );
    }
    try {
      const status = await adopt(dest, provenance);
      return ok(`${created}, and Foreman's worker for it is ${status.workerState}.`);
    } catch (error) {
      if (error instanceof ForemanUnavailableError) {
        return ok(`${created}, but Foreman became unreachable, so no worker was started: ${message(error)}`);
      }
      return fail(`${created}, but Foreman couldn't start a worker: ${message(error)}`);
    }
  },
);

server.registerTool(
  "list_repos",
  {
    title: "List Foreman repos",
    description:
      "List the repositories Foreman knows about, each with its worker state and (for copies) how it was created.",
    inputSchema: {},
  },
  async () => {
    let info;
    try {
      info = await describe();
    } catch (error) {
      if (error instanceof ForemanUnavailableError) {
        return fail(`Foreman isn't running: ${message(error)}`);
      }
      return fail(`Couldn't query Foreman: ${message(error)}`);
    }

    const lines = [`Foreman scan directory: ${info.scanDirectory}`, `Repos (${info.repos.length}):`];
    for (const repo of info.repos) {
      let line = `- ${repo.name} [${repo.workerState}${repo.pid ? ` pid ${repo.pid}` : ""}]`;
      if (repo.provenance) {
        const parent = path.basename(repo.provenance.parentRepoID);
        line += ` — ${repo.provenance.kind} of ${parent} on ${repo.provenance.branch}`;
      }
      lines.push(line);
    }
    return ok(lines.join("\n"));
  },
);

server.registerTool(
  "remove_repo_copy",
  {
    title: "Remove a repo copy",
    description:
      "Remove a copy Foreman created: it stops the worker, then removes the worktree (git) or moves the clone to the Trash. Only works on copies made via spinup_repo_copy.",
    inputSchema: {
      path: z.string().describe("Absolute path of the copy to remove."),
    },
  },
  async ({ path: target }) => {
    const resolved = path.resolve(target);
    try {
      const removed = await removeCopy(resolved);
      return ok(`Removed the copy at ${removed}.`);
    } catch (error) {
      if (error instanceof ForemanUnavailableError) {
        return fail(
          `Foreman must be running to remove a copy (it stops the worker first): ${message(error)}`,
        );
      }
      return fail(`Couldn't remove the copy: ${message(error)}`);
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
log("server ready");
