import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// GUI-launched processes (which is how Cursor spawns this server) don't
// inherit the shell PATH, so locate git at its known install paths, falling
// back to the PATH lookup.
const GIT_SEARCH_PATHS = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"];

let cachedGitPath: string | undefined;

function gitPath(): string {
  if (cachedGitPath) return cachedGitPath;
  cachedGitPath = GIT_SEARCH_PATHS.find((candidate) => existsSync(candidate)) ?? "git";
  return cachedGitPath;
}

/// A git invocation that exited non-zero, carrying its stderr so the reason
/// isn't swallowed.
export class GitError extends Error {}

async function git(args: string[], cwd?: string): Promise<string> {
  try {
    const { stdout } = await execFileAsync(gitPath(), args, {
      cwd,
      maxBuffer: 32 * 1024 * 1024,
    });
    return stdout.trim();
  } catch (error) {
    const stderr = (error as { stderr?: string }).stderr?.trim();
    throw new GitError(stderr && stderr.length > 0 ? stderr : String(error));
  }
}

export async function isGitRepo(dir: string): Promise<boolean> {
  try {
    return (await git(["-C", dir, "rev-parse", "--is-inside-work-tree"])) === "true";
  } catch {
    return false;
  }
}

/// The repository root that contains `dir`.
export async function repoToplevel(dir: string): Promise<string> {
  return git(["-C", dir, "rev-parse", "--show-toplevel"]);
}

export async function branchExists(repo: string, branch: string): Promise<boolean> {
  try {
    await git(["-C", repo, "show-ref", "--verify", "--quiet", `refs/heads/${branch}`]);
    return true;
  } catch {
    return false;
  }
}

export async function originURL(repo: string): Promise<string | undefined> {
  try {
    return await git(["-C", repo, "remote", "get-url", "origin"]);
  } catch {
    return undefined;
  }
}

/// Adds a worktree at `dest`. A new branch is created (`-b`) unless `branch`
/// already exists, in which case it's checked out into the worktree.
export async function addWorktree(
  repo: string,
  dest: string,
  branch: string,
  baseRef: string | undefined,
): Promise<void> {
  if (await branchExists(repo, branch)) {
    await git(["-C", repo, "worktree", "add", dest, branch]);
  } else {
    const args = ["-C", repo, "worktree", "add", "-b", branch, dest];
    if (baseRef) args.push(baseRef);
    await git(args);
  }
}

export async function cloneRepo(source: string, dest: string): Promise<void> {
  await git(["clone", source, dest]);
}

/// Ensures `branch` is checked out in `repo`, creating it (from `baseRef` when
/// given) if it doesn't exist yet.
export async function checkoutBranch(
  repo: string,
  branch: string,
  baseRef: string | undefined,
): Promise<void> {
  if (await branchExists(repo, branch)) {
    await git(["-C", repo, "checkout", branch]);
  } else {
    const args = ["-C", repo, "checkout", "-b", branch];
    if (baseRef) args.push(baseRef);
    await git(args);
  }
}

export async function setOriginURL(repo: string, url: string): Promise<void> {
  await git(["-C", repo, "remote", "set-url", "origin", url]);
}
