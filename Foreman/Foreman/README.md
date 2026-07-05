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

- **Sidebar** — one row per discovered repo: status dot (gray stopped, yellow
  stopping/restarting, green running, red failed — flipping a stopping worker
  back on queues a restart for when the old process exits) and the worker's
  on/off switch.
- **Detail pane** (select a repo) — the worker's status, pid and live uptime,
  the failure reason when it died, the repo path, the exact `cursor-agent`
  command the next start will spawn, the options editor inline, and a live
  tail of the worker's log (`~/Library/Logs/Foreman/<repo>.log`, refreshed
  every second while the window is visible, with an Open File button).
- **Worker options** — mirrors the `cursor agent worker` CLI flags: display
  name, pool mode + pool name, `key=value` labels, idle release timeout, and
  verbose startup logs. Editable while the worker is stopped — options apply
  on the next start.
- **Toolbar** — a "Preventing sleep" badge while the sleep assertion is held,
  Rescan, Settings (opens the standard settings window: the scan directory
  and an explicit `cursor-agent` path, empty = auto-detect, applied as
  fields commit), and Quit.

## Lifecycle

- On launch, Foreman restores the saved configuration and restarts the workers
  that were enabled last time.
- Quitting stops every worker (stop-on-quit: the app owns its processes and
  never leaves orphans).
- The repo list refreshes every time the window is opened or focused, and on
  **Rescan**.
- A worker whose repo vanishes from the scan (deleted, renamed, or the scan
  directory changed) is stopped on the next rescan — no worker keeps running
  without a row to control it. Saved toggles and options for repos deleted
  from the current scan directory are pruned; settings for other scan
  directories are kept and re-apply when you switch back.

## Limitations

- The sleep assertion blocks *idle* sleep only (like `caffeinate -i`); closing
  the lid still sleeps the machine.
- Workers are not restarted automatically if they crash — the row turns red
  with the failure reason, and flipping the switch retries.
- `cursor-agent` must already be installed and logged in; Foreman launches it
  but doesn't manage authentication.
