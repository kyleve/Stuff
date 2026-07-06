# ForemanCore

The model layer for **Foreman**, the macOS menu bar app that spins up
[Cursor local agent workers](https://cursor.com/docs) (`cursor-agent worker
start`) for the git repositories in a development directory. ForemanCore owns
everything that isn't SwiftUI, organized as a tree of `@MainActor
@Observable` objects rooted in `ForemanServices`: global settings, repository
discovery, one `Repo` per repository owning its `Worker` process, plus
configuration persistence, the sleep assertion, and the logging facade. The
app target (`Foreman/Foreman`) holds only views and a thin session facade
that binds this tree.

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

// The root owns everything: settings, discovery, workers, persistence.
let services = ForemanServices(
    configStore: .applicationSupport(),
    logDirectory: ForemanServices.defaultLogDirectory,
)
services.start() // first scan + restart previously-enabled workers

// Each discovered repo is an observable object owning its worker.
let repo = services.repos[0]
repo.isEnabled = true            // starts the worker, persists the intent
print(repo.worker.state)         // .running(pid:since:)
print(repo.worker.logFileURL)    // ~/Library/Logs/Foreman/Thing.log

// Render the CLI invocation the next start will use.
let argv = repo.options.arguments(workerDirectory: repo.rootURL)
// → ["worker", "--worker-dir", "/Users/you/Development/Thing", "start"]
```

## Public API

- **`ForemanServices`** — the root of the model tree. Loads the configuration
  in `init`, `start()` runs the first scan and restarts previously-enabled
  workers, `rescan()` re-lists the scan directory, `stopAll()` is the quit
  path. Funnels every persisted mutation (repo toggles/options, settings)
  into the saved JSON, recomputes the sleep assertion on every worker
  transition, and surfaces tree-level problems (unreadable config, failed
  scan, failed save) on the observable `issueMessage`. `startsAtLogin` is a
  two-way property over the login item (see `LoginItemController`), with
  `loginItemNeedsApproval` and a dedicated `loginItemError` (login failures
  surface here, not on the shared `issueMessage`); `refreshLoginItemStatus()`
  re-reads it from the OS and `openSystemSettingsLoginItems()` jumps to the
  approval UI. The MCP-facing intents (`describe()`,
  `adoptAndStartWorker(at:provenance:)`, `removeCopy(at:)`) live here too —
  see [MCP control](#mcp-control).
- **`Repo` / `RepoID`** — one discovered repository as an `@Observable`
  object: identity (`name`, `rootURL`, typed `RepoID` = canonical absolute
  path), the persisted intent (`isEnabled`, `isFavorite`, `options` —
  mutations persist automatically; `isEnabled` also starts/stops the worker,
  while `isFavorite` is pure sidebar-ordering metadata), and its `Worker`.
  Transient intents
  that don't change the persisted desired state: `retry()` (fresh attempt
  for an enabled repo in `.failed`) and `restart()` (respawn a running
  worker with the current options — the apply path for options edited while
  running). `provenance` is a `CopyProvenance?` recorded when the repo is an
  MCP-created copy (persists on assignment); `nil` for ordinary repos.
- **`Worker`** — the per-repo process: `start(options:executable:)`,
  `stop()`, an observable `state` enum (`stopped` / `running(pid:since:)` /
  `stopping(restartPending:)` / `failed(reason:)`), and `logFileURL`.
  Worker stdout+stderr append to `~/Library/Logs/Foreman/<repo>.log` with
  start/exit marker lines. A spawn failure lands in `.failed` (and the log);
  a user-requested stop reads as `.stopped` even though SIGTERM technically
  kills the CLI by signal. A start requested while the worker is still
  stopping queues one restart, applied when the old process exits (and
  cancelled by another stop), so a quick off-then-on flip restarts instead
  of silently dying. `recordStartFailure(reason:)` lets callers land
  pre-spawn failures (like a missing executable) in the same `.failed`
  state as spawn failures.
- **`RepoDiscovery` / `ScannedRepo`** — the stateful repo list: `rescan(in:)`
  updates `repos`, reusing existing `Repo` instances by id (live workers
  survive a rescan) and stopping workers whose repo vanished. The static
  `scan(_:)` is the pure listing: git repositories directly inside a scan
  directory (a subdirectory with a `.git` entry — directory or file, so
  worktrees count) as `ScannedRepo` values. Hidden directories are skipped;
  nesting is not searched. Throws when the scan directory can't be listed.
- **`RepoSection`** — the pure sidebar ordering rule. `sections(from:)` groups
  the discovered repos into an `.enabled` section on top and a `.disabled` one
  below, floating favorites to the top of each (stable — otherwise the
  name-sorted order is preserved) and omitting an empty section. `ForemanServices`
  exposes it as `repoSections`.
- **`AppSettings`** — observable global settings: `scanDirectory` (default
  `~/Development` via `resolvedScanDirectory`) and `agentExecutable` (`nil`
  = auto-locate). Assignments persist and — for the scan directory —
  rescan automatically.
- **`WorkerOptions`** — the per-repo worker flags, mirroring the
  `cursor agent worker` CLI one-to-one: `displayName` (`--name`),
  `assignment` (`.shared` or `.pool(name:)` → `--pool` / `--pool-name`),
  `labels` (`--label key=value`), `idleReleaseTimeoutSeconds`
  (`--idle-release-timeout`), and `verbose` (`start --verbose`).
  `arguments(workerDirectory:)` renders the full argv; `.standard` is the
  CLI-default configuration.
- **`RepoConfiguration` / `ForemanConfiguration`** — everything Foreman
  persists.   `RepoConfiguration` is the single per-repo record (`isEnabled`,
  `isFavorite`, `options`, and an optional `provenance`) — one struct instead
  of parallel maps keyed by `RepoID`, so the flags and options can't drift
  apart. A recorded `provenance` makes the record non-`.standard`, so a copy's
  origin survives even when its flags are otherwise default. `ForemanConfiguration`
  holds the scan directory (default `~/Development`), an explicit
  `cursor-agent` executable (or `nil` for auto-locate), and
  `repos: [RepoID: RepoConfiguration]`; a repo left at
  `RepoConfiguration.standard` has no entry (absence reads identically).
  `prune(discovered:under:)` drops entries for repos that vanished from the
  scan directory while keeping entries outside it (another directory's
  history, re-applied when the user switches back).
- **`WorkerConfigStore`** — throwing `load()` / `save(_:)` of the configuration
  JSON under `~/Library/Application Support/com.stuff.foreman/`. A missing
  file loads as `ForemanConfiguration.initial` (first launch); a corrupt file
  throws rather than silently resetting.
- **`SleepInhibitor`** — while any worker is live the root holds a
  `ProcessInfo` `.idleSystemSleepDisabled` activity (the `caffeinate -i`
  equivalent), so the machine won't doze off mid-agent-run. Display sleep and
  an explicit lid close are unaffected. The observable `isActive` backs the
  app's "preventing sleep" indicator.
- **`LoginItemController`** — reflects and toggles whether Foreman launches at
  login, wrapping `SMAppService.mainApp` (no helper bundle or entitlement
  needed for the main app). The OS owns the real state, so the observable
  `status` (a `LoginItemStatus`: `enabled` / `requiresApproval` /
  `notRegistered`) is read from the service and `refresh()` re-reads it (the
  user can change it in System Settings). `isEnabled` treats a pending
  (`requiresApproval`) item as on — not off — with `needsApproval` flagging
  that the user still has to confirm it (`openSystemSettingsLoginItems()`
  jumps there). `setEnabled(_:)` registers/unregisters and re-syncs so a
  failed attempt never reads as falsely on. The real service sits behind an
  `@_spi(Testing)` `LoginItemBackend` so tests inject a double.
- **`CursorAgentLocator`** — resolves the `cursor-agent` executable. GUI apps
  don't inherit the shell `PATH`, so it checks the CLI's known install
  locations (`~/.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin`); an
  explicitly configured path is validated and a stale one throws
  `NotFoundError` instead of falling back silently.
- **`LogTailReader`** — `tail(of:maxBytes:)` returns the end of a log file
  (starting on a line boundary) for display without loading the whole file;
  `nil` when the file doesn't exist yet.
- **`ForemanLog`** — the logging facade over LogKit: `ForemanLog.channel(_:)`
  with a typed `Category`, subsystem `com.stuff.foreman`.

## MCP control

The [`foreman-mcp`](../foreman-mcp) server drives Foreman over a local
unix-domain socket. ForemanCore owns the transport-agnostic half; the app
target owns the socket itself (see [the app's control server](../Foreman/README.md#mcp-control-socket)).

- **`CopyProvenance`** — how an MCP-created copy came to be, modeled as one
  value so invalid combinations can't be spelled: `kind` (`.worktree` /
  `.clone`), `parentRepoID`, and `branch`. Persisted on `RepoConfiguration`
  and mirrored on `Repo.provenance`; its absence is an ordinary repo.
- **`ControlRequest` / `ControlResponse`** — the `Codable` wire protocol
  (JSON-lines: one request, one response). Requests are `describe`, `adopt`
  (path + provenance), and `removeCopy` (path); responses carry a
  `DescribeResultDTO`, a `RepoStatusDTO`, a removed path, or an error string.
  `CopyProvenanceDTO` / `RepoStatusDTO` / `DescribeResultDTO` are the flat
  transfer shapes; `RepoStatusDTO(repo:)` projects a live `Repo`. **This is the
  contract mirrored in `foreman-mcp`'s `src/control.ts` — keep them in sync.**
- **`ControlRequestHandler`** — maps a decoded `ControlRequest` to the matching
  `ForemanServices` intent on the main actor and wraps the outcome (or a
  `ControlError`) in a `ControlResponse`.
- **`ForemanServices` intents** — `describe()` returns the scan directory plus
  every repo's worker state and provenance; `adoptAndStartWorker(at:provenance:)`
  validates the path is a direct subdirectory of the scan directory (throwing a
  `ControlError` otherwise), records the provenance, `rescan()`s, and enables
  the worker; `removeCopy(at:)` stops and drains the worker, then removes the
  copy (via `RepoCopyRemoving`) and `rescan()`s. `removeCopy` is gated on
  recorded provenance, so Foreman only ever removes copies it created.
  `controlSocketURL` is the shared socket path.
- **`RepoCopyRemoving` / `SystemRepoCopyRemover`** — the removal seam:
  `git worktree remove` for a worktree, move-to-Trash for a clone. Injected
  into `ForemanServices` so tests substitute a recorder instead of touching the
  filesystem.

## Localization

User-facing strings — worker failure reasons (`Worker`), the scan/save/login
errors and config-load fallback (`ForemanServices`), and
`CursorAgentLocator.NotFoundError` — come from `Sources/Resources/Localizable.xcstrings`
via Xcode 26's generated symbols (`String(localized: .workerExitedWithCode(code:))`,
etc.). The catalog is a `.process`-ed resource, so `defaultLocalization` and the
module bundle are wired automatically — no `bundle: .module`. Symbol generation
runs under both the Tuist / `xcodebuild` flow and a plain `swift build` (the
Swift 6.2 toolchain builds SwiftPM targets with the Swift Build engine, which
generates the symbols), so the module compiles either way.

## Contracts & limitations

- `WorkerOptions.arguments(workerDirectory:)` is the single place that knows
  the CLI flag spelling — worker-level flags precede the `start` subcommand,
  `--verbose` follows it.
- An empty pool name and a zero idle timeout defer to the CLI's own defaults
  (pool "default", idle release disabled) by omitting the flag.
- Discovery is intentionally shallow: one directory level, no recursion into
  nested repositories.
