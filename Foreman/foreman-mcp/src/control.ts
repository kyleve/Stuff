import net from "node:net";
import { homedir } from "node:os";
import path from "node:path";

/// The wire contract mirrors `ForemanCore/Sources/ControlProtocol.swift`.
/// Keep the two in sync when either side changes.

export interface CopyProvenanceWire {
  kind: "worktree" | "clone";
  parentRepoID: string;
  branch: string;
}

export interface RepoStatus {
  id: string;
  name: string;
  path: string;
  enabled: boolean;
  workerState: string;
  pid?: number;
  failureReason?: string;
  provenance?: CopyProvenanceWire;
}

export interface DescribeResult {
  scanDirectory: string;
  repos: RepoStatus[];
}

export type ControlRequest =
  | { command: "describe" }
  | { command: "adopt"; path: string; provenance: CopyProvenanceWire }
  | { command: "removeCopy"; path: string };

type ControlResponse =
  | { ok: true; kind: "describe"; describe: DescribeResult }
  | { ok: true; kind: "repo"; repo: RepoStatus }
  | { ok: true; kind: "removed"; path: string }
  | { ok: false; error: string };

/// Thrown when Foreman isn't running / the socket can't be reached — callers
/// degrade gracefully (the git copy still succeeds, just no worker starts).
export class ForemanUnavailableError extends Error {}

/// Thrown when Foreman replied but reported a failure (`ok: false`).
export class ForemanError extends Error {}

export function controlSocketPath(): string {
  return (
    process.env.FOREMAN_CONTROL_SOCKET ??
    path.join(homedir(), "Library/Application Support/com.stuff.foreman/control.sock")
  );
}

function sendControlRequest(
  request: ControlRequest,
  timeoutMs = 20_000,
): Promise<ControlResponse> {
  const socketPath = controlSocketPath();
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ path: socketPath });
    let buffer = "";
    let settled = false;

    const finish = (action: () => void) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      action();
    };

    const timer = setTimeout(() => {
      finish(() =>
        reject(new ForemanUnavailableError(`Foreman didn't respond within ${timeoutMs}ms.`)),
      );
    }, timeoutMs);

    socket.on("connect", () => {
      socket.write(`${JSON.stringify(request)}\n`);
    });

    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newline = buffer.indexOf("\n");
      if (newline < 0) return;
      const line = buffer.slice(0, newline);
      finish(() => {
        try {
          resolve(JSON.parse(line) as ControlResponse);
        } catch (error) {
          reject(new ForemanError(`Couldn't parse Foreman's reply: ${String(error)}`));
        }
      });
    });

    socket.on("error", (error: NodeJS.ErrnoException) => {
      finish(() => {
        if (error.code === "ENOENT" || error.code === "ECONNREFUSED") {
          reject(
            new ForemanUnavailableError(
              "Foreman isn't running (its control socket is unavailable).",
            ),
          );
        } else {
          reject(new ForemanUnavailableError(`Couldn't reach Foreman: ${error.message}`));
        }
      });
    });

    socket.on("end", () => {
      finish(() =>
        reject(new ForemanError("Foreman closed the connection without a reply.")),
      );
    });
  });
}

export async function describe(): Promise<DescribeResult> {
  const response = await sendControlRequest({ command: "describe" });
  if (response.ok && response.kind === "describe") return response.describe;
  throw failureFor(response, "describe");
}

export async function adopt(
  copyPath: string,
  provenance: CopyProvenanceWire,
): Promise<RepoStatus> {
  const response = await sendControlRequest({
    command: "adopt",
    path: copyPath,
    provenance,
  });
  if (response.ok && response.kind === "repo") return response.repo;
  throw failureFor(response, "adopt");
}

export async function removeCopy(copyPath: string): Promise<string> {
  const response = await sendControlRequest({ command: "removeCopy", path: copyPath });
  if (response.ok && response.kind === "removed") return response.path;
  throw failureFor(response, "removeCopy");
}

function failureFor(response: ControlResponse, command: string): Error {
  if (!response.ok) return new ForemanError(response.error);
  return new ForemanError(`Unexpected reply to ${command}: ${JSON.stringify(response)}`);
}
