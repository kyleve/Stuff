# ForemanCore – Module Shape

ForemanCore is the model/controller layer for the Foreman menu bar app: git
repository discovery, per-repo `cursor-agent worker` options and argv
rendering, configuration persistence, and the logging facade. The SwiftUI
layer lives in the app target (`Foreman/Foreman`); see
[`README.md`](README.md) for the narrative and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + LogKit only.** No SwiftUI, no AppKit UI — views and the
  `@Observable` session belong to the app target. ForemanCore is the only
  macOS-only package library in the repo (`.macOS(.v26)` in
  [`Package.swift`](../../Package.swift)); everything else stays iOS.
- The hostless macOS test bundle `ForemanCoreTests` is declared directly in
  [`Project.swift`](../../Project.swift) (the `unitTests` helper is
  iOS/StuffTestHost-specific) and runs via the `Foreman-macOS-Tests` scheme.

## Key types

- [`RepoDiscovery`](Sources/RepoDiscovery.swift) – `repos(in:)` scans one
  directory level for subdirectories containing a `.git` entry (directory or
  file, so worktrees/submodules count), skips hidden entries, sorts
  case-insensitively by name, and **throws** when the directory can't be
  listed. `Repo.id` is a typed `RepoID` (canonical absolute path), not a raw
  `String`.
- [`WorkerOptions`](Sources/WorkerOptions.swift) – Codable per-repo flags.
  `Assignment` is a single enum (`.shared` / `.pool(name:)`) so pool
  registration and pool name can't drift apart; labels are a named `Label`
  struct, not tuples. `arguments(workerDirectory:)` is the **only** place that
  spells CLI flags: worker-level flags before the `start` subcommand,
  `--verbose` after it.
- [`ForemanConfiguration` / `WorkerConfigStore`](Sources/WorkerConfigStore.swift)
  – the persisted state (scan directory, explicit agent executable,
  enabled-repo set, per-repo options) and its JSON store. `load()`
  distinguishes *missing* (first launch → `.initial`) from *corrupt* (throws);
  don't collapse the two.
- [`WorkerSupervisor`](Sources/WorkerSupervisor.swift) – `@MainActor
  @Observable` owner of the worker processes. Per-repo state is the single
  `WorkerState` enum (`stopped` / `running(pid:)` / `stopping` /
  `failed(reason:)` — no `.starting`: spawning is synchronous on the main
  actor, so an in-between state would be unobservable); the private `Handle`
  carries the `Process`, its log
  `FileHandle`, and the `stopRequested` bit that turns a SIGTERM death into
  `.stopped` instead of `.failed`. Worker output appends to
  `<logDirectory>/<repo name>.log` with start/exit markers. `start` doesn't
  throw — a spawn failure lands in `.failed` and the log, so the state *is*
  the caller-observable result.
- [`SleepInhibitor`](Sources/SleepInhibitor.swift) – idempotent wrapper around
  `ProcessInfo.beginActivity(.idleSystemSleepDisabled)`. The supervisor
  recomputes it after every state change (`updateSleepInhibition`), so the
  assertion is held exactly while ≥1 worker is live. The `@_spi(Testing)`
  init swaps the real assertion for begin/end observers.
- [`CursorAgentLocator`](Sources/CursorAgentLocator.swift) – resolves the
  executable from known install paths (GUI apps don't inherit shell `PATH`).
  An explicit configured path is *validated*, and a stale one throws rather
  than silently falling back to auto-locate.
- [`ForemanLog`](Sources/ForemanLog.swift) – LogKit facade, subsystem
  `com.stuff.foreman`, typed `Category` enum. Add a case to introduce a new
  category; never log with raw strings.

## Invariants & behaviors to preserve

- **Absence vs failure.** A repo with no customized options reads as
  `WorkerOptions.standard` (expected absence); an unreadable or undecodable
  config file throws (real failure). Keep that split — no `try?` or silent
  resets.
- **CLI defaults are deferred to, not duplicated.** An empty pool name or zero
  idle timeout omits the flag so the CLI's own default applies; don't bake the
  CLI's default values into rendered argv.
- **`RepoID` everywhere.** Config maps and supervisor lookups key by `RepoID`;
  never key by display name or raw path strings.
- **Stop intent decides the end state.** A worker that dies after
  `stop(_:)`/`stopAll()` reads as `.stopped` (SIGTERM kills the CLI by
  signal, but the user asked for it); an *unrequested* death is `.failed`
  with the exit code or signal in the reason. Don't collapse the two.
- **The sleep assertion tracks liveness, not toggles.** It's recomputed from
  `states` after every transition — held while any worker is live, released
  when the last one ends, never taken per-worker.

## Conventions

Follow the root rules: exhaustive `switch` (no bare `default:`), small named
structs over tuples, typed identifiers, throwing APIs over benign-looking
defaults, `@_spi(Testing)` for test-only hooks.

## Testing

Swift Testing in [`Tests/`](Tests) (never XCTest), hostless on macOS — run
`tuist test ForemanCoreTests -- -destination 'platform=macOS'`. Tests are 1:1
with source files; shared fixtures live in
[`ForemanCoreTestSupport.swift`](Tests/ForemanCoreTestSupport.swift)
(`makeTemporaryDirectory()`, `waitUntil(_:condition:)`). Filesystem tests
build real fixtures in unique temp directories; nothing touches the user's
`~/Development` or Application Support.
