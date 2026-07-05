# ForemanCore

The model/controller layer for **Foreman**, the macOS menu bar app that spins
up [Cursor local agent workers](https://cursor.com/docs) (`cursor-agent worker
start`) for the git repositories in a development directory. ForemanCore owns
everything that isn't SwiftUI: repository discovery, per-repo worker options,
configuration persistence, and the logging facade. The app target
(`Foreman/Foreman`) holds only views and an observable session model.

ForemanCore is macOS-only (macOS 26+) and depends on Foundation +
[`LogKit`](../../Shared/LogKit).

## Installation

`ForemanCore` is a local SPM library in this repo (`Foreman/ForemanCore`). Add
it to a target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourTarget", dependencies: [.target(name: "ForemanCore")])
```

## Quick start

```swift
import ForemanCore

// Load (or default) the persisted configuration.
let store = WorkerConfigStore.applicationSupport()
var configuration = try store.load()

// Find the git repositories to offer workers for.
let repos = try RepoDiscovery().repos(in: configuration.resolvedScanDirectory)

// Render the CLI invocation for one of them.
let options = configuration.options(for: repos[0].id)
let argv = options.arguments(workerDirectory: repos[0].rootURL)
// → ["worker", "--worker-dir", "/Users/you/Development/Thing", "start"]
```

## Public API

- **`RepoDiscovery`** — `repos(in:)` lists the git repositories directly inside
  a scan directory (a subdirectory with a `.git` entry — directory or file, so
  worktrees count). Hidden directories are skipped; nesting is not searched.
  Throws when the scan directory can't be listed.
- **`Repo` / `RepoID`** — a discovered repository (name + root URL) and its
  typed identifier (the canonical absolute path). `RepoID` keys the config
  maps so ids can't silently typo into new entries.
- **`WorkerOptions`** — the per-repo worker flags, mirroring the
  `cursor agent worker` CLI one-to-one: `displayName` (`--name`),
  `assignment` (`.shared` or `.pool(name:)` → `--pool` / `--pool-name`),
  `labels` (`--label key=value`), `idleReleaseTimeoutSeconds`
  (`--idle-release-timeout`), and `verbose` (`start --verbose`).
  `arguments(workerDirectory:)` renders the full argv; `.standard` is the
  CLI-default configuration.
- **`ForemanConfiguration`** — everything Foreman persists: the scan directory
  (default `~/Development`), an explicit `cursor-agent` executable (or `nil`
  for auto-locate), the enabled-repo set, and the per-repo options map.
  `prune(discovered:under:)` drops entries for repos that vanished from the
  scan directory while keeping entries outside it (another directory's
  history, re-applied when the user switches back).
- **`WorkerConfigStore`** — throwing `load()` / `save(_:)` of the configuration
  JSON under `~/Library/Application Support/com.stuff.foreman/`. A missing
  file loads as `ForemanConfiguration.initial` (first launch); a corrupt file
  throws rather than silently resetting.
- **`WorkerSupervisor`** — the `@MainActor @Observable` controller owning one
  worker process per enabled repo: `start(repo:options:executable:)`,
  `stop(_:)`, `stopAll()`, and an observable `states` map. Each repo's state
  is a single `WorkerState` enum (`stopped` / `running(pid:since:)` /
  `stopping(restartPending:)` / `failed(reason:)`). Worker stdout+stderr
  append to `~/Library/Logs/Foreman/<repo>.log` with start/exit marker lines.
  A spawn failure lands in `.failed` (and the log); a user-requested stop
  reads as `.stopped` even though SIGTERM technically kills the CLI by
  signal. A start requested while the worker is still stopping queues one
  restart, applied when the old process exits (and cancelled by another
  stop), so a quick off-then-on flip restarts instead of silently dying.
  `recordStartFailure(_:reason:)` lets callers land pre-spawn failures (like
  a missing executable) in the same `.failed` state as spawn failures.
- **`SleepInhibitor`** — while any worker is live the supervisor holds a
  `ProcessInfo` `.idleSystemSleepDisabled` activity (the `caffeinate -i`
  equivalent), so the machine won't doze off mid-agent-run. Display sleep and
  an explicit lid close are unaffected. The observable `isActive` backs the
  app's "preventing sleep" indicator.
- **`CursorAgentLocator`** — resolves the `cursor-agent` executable. GUI apps
  don't inherit the shell `PATH`, so it checks the CLI's known install
  locations (`~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`); an
  explicitly configured path is validated and a stale one throws
  `NotFoundError` instead of falling back silently.
- **`LogTailReader`** — `tail(of:maxBytes:)` returns the end of a log file
  (starting on a line boundary) for display without loading the whole file;
  `nil` when the file doesn't exist yet.
- **`ObservationPump`** — re-registering `withObservationTracking`: calls
  `onChange` on the main actor after every change to the properties read by
  `tracking`, not just the first. Lets non-SwiftUI code react to
  `@Observable` state; the app uses one to keep its AppKit status-item icon
  current.
- **`ForemanLog`** — the logging facade over LogKit: `ForemanLog.channel(_:)`
  with a typed `Category`, subsystem `com.stuff.foreman`.

## Contracts & limitations

- `WorkerOptions.arguments(workerDirectory:)` is the single place that knows
  the CLI flag spelling — worker-level flags precede the `start` subcommand,
  `--verbose` follows it.
- An empty pool name and a zero idle timeout defer to the CLI's own defaults
  (pool "default", idle release disabled) by omitting the flag.
- Discovery is intentionally shallow: one directory level, no recursion into
  nested repositories.
