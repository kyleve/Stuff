# Foreman

A macOS **menu bar app** for spinning up [Cursor local agent
workers](https://cursor.com/docs) without touching a terminal. Foreman lists
every git repository in your development directory (default `~/Development`);
each row has a switch that starts or stops a `cursor-agent worker start`
process for that repo, plus an editor for the worker's CLI options. While any
worker is running, Foreman holds a sleep assertion so the Mac won't idle-sleep
mid-agent-run.

All behavior lives in [`ForemanCore`](../ForemanCore); this target is the thin
SwiftUI shell.

## Running

```bash
./ide --no-open              # regenerate the Xcode project
mise exec -- tuist build Foreman
```

or run the `Foreman` scheme from Xcode. The app lives in the menu bar (a
hammer icon — filled while any worker is live). Clicking the icon toggles a
regular, resizable window; a Dock icon appears while the window is open (the
price of reliable keyboard focus for a menu bar app) and disappears when it's
closed. Closing the window just hides it — the app keeps running until Quit.

## What's in the window

- **Sidebar** — repos grouped into an **Enabled** section on top and a
  **Disabled** one below, with favorites floated to the top of each; rows glide
  between groups as you toggle or favorite them. Each row shows a status dot
  (gray stopped, yellow stopping/restarting, green running, red failed —
  flipping a stopping worker back on queues a restart for when the old process
  exits), the worker's on/off switch, and a star on favorited repos. Repos that
  Foreman created as copies (via the MCP — see below) carry a small
  worktree/clone badge whose tooltip names the parent repo and branch.
  Right-click a row to favorite or unfavorite it.
- **Detail pane** (select a repo) — the worker's status, pid and live uptime,
  the failure reason when it died, the repo path, the exact `cursor-agent`
  command the next start will spawn, the options editor inline, and a live
  tail of the worker's log (`~/Library/Logs/Foreman/<repo>.log`, refreshed
  every second while the window is visible, with an Open File button). The
  status row offers **Retry** when an enabled worker failed and **Restart**
  while it's running (a fresh process with the saved options); neither
  changes the on/off switch. A toolbar star favorites the repo (mirrors the
  sidebar's right-click toggle). For a copy Foreman created, a **Copy** section
  shows how it was made (worktree vs clone, the parent repo, the branch) and a
  **Remove Copy…** button that — after a confirmation — stops the worker and
  removes the worktree (git) or moves the clone to the Trash; failures surface
  in an alert.
- **Worker options** — mirrors the `cursor agent worker` CLI flags: display
  name, pool mode + pool name, `key=value` labels, idle release timeout, and
  verbose startup logs. Editable while the worker is stopped — options apply
  on the next start.
- **Toolbar** — a "Preventing sleep" badge while the sleep assertion is held,
  Rescan, Settings (opens the settings window — see below), and Quit.

## Settings

The settings window is a macOS System-Settings-style sidebar with three panes.
The *Launch at login* toggle applies immediately; the path settings open a
small editor sheet that commits only on **Save** (Cancel or Escape discards).

- **General** — *Launch Foreman at login*. Registers Foreman as a login item
  via `SMAppService`, so it starts (and restores your enabled workers) when
  you log in. If macOS needs you to approve the item first, the pane says so
  and links straight to System Settings; a failed toggle shows its error here.
- **Repositories** — the directory scanned for git repositories (empty =
  `~/Development`), edited via a sheet with a folder picker.
- **Agent** — an explicit `cursor-agent` executable path (empty = auto-detect),
  edited via a sheet.

## Lifecycle

- On launch, Foreman restores the saved configuration and restarts the workers
  that were enabled last time. With *Launch Foreman at login* on, this happens
  automatically after you log in.
- The MCP control socket is started after launch and closed (its file removed)
  on quit.
- Quitting stops every worker (stop-on-quit: the app owns its processes and
  never leaves orphans).
- The repo list refreshes every time the window is opened or focused, and on
  **Rescan**.
- A worker whose repo vanishes from the scan (deleted, renamed, or the scan
  directory changed) is stopped on the next rescan — no worker keeps running
  without a row to control it. Saved toggles and options for repos deleted
  from the current scan directory are pruned; settings for other scan
  directories are kept and re-apply when you switch back.

## MCP control socket

On launch Foreman starts a small local control server on a unix-domain socket
at `~/Library/Application Support/com.stuff.foreman/control.sock` (JSON-lines),
and tears it down on quit — both wired through `ForemanSession`. The
[`foreman-mcp`](../foreman-mcp) server connects to it so a Cursor agent can spin
up a worktree/clone copy of its repo and have Foreman start a worker on it; the
copy then appears in the sidebar like any other repo. The transport-agnostic
protocol and the intents behind it (`describe` / `adopt` / `removeCopy`) live in
[`ForemanCore`](../ForemanCore/README.md#mcp-control); this target only owns the
socket. A stale socket file (e.g. after a hard kill) is unlinked on the next
start, so a leftover file never blocks binding.

## Localization

All of Foreman's on-screen copy lives in
[`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings) and is
referenced through Xcode 26's type-safe generated symbols (the
`STRING_CATALOG_GENERATE_SYMBOLS` build setting) — the views hold no English
literals, so retitling a button is a one-line catalog edit. The app name and
the `cursor-agent` command stay as-is.

## Limitations

- The sleep assertion blocks *idle* sleep only (like `caffeinate -i`); closing
  the lid still sleeps the machine.
- Workers are not restarted automatically if they crash — the row turns red
  with the failure reason, and Retry (or flipping the switch) starts a fresh
  attempt.
- `cursor-agent` must already be installed and logged in; Foreman launches it
  but doesn't manage authentication.
