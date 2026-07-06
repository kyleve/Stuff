# ForemanCore – Module Shape

ForemanCore is the model layer for the Foreman menu bar app: a tree of
`@MainActor @Observable` objects rooted in `ForemanServices` (settings, git
repository discovery, per-repo workers), plus the value types they persist
and the logging facade. The SwiftUI layer lives in the app target
(`Foreman/Foreman`) and binds the tree directly; see [`README.md`](README.md)
for the narrative and usage.

```
ForemanServices ── AppSettings
       ├────────── RepoDiscovery ── [Repo] ── Worker
       ├────────── WorkerConfigStore (ForemanConfiguration JSON)
       └────────── SleepInhibitor
```

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + Observation + LogKit only.** No SwiftUI, no AppKit UI —
  views and the thin session facade belong to the app target; the observable
  model tree lives here. ForemanCore is the only macOS-only package library
  in the repo (`.macOS(.v26)` in [`Package.swift`](../../Package.swift));
  everything else stays iOS.
- The hostless macOS test bundle `ForemanCoreTests` is declared directly in
  [`Project.swift`](../../Project.swift) (the `unitTests` helper is
  iOS/StuffTestHost-specific) and runs via the `Foreman-macOS-Tests` scheme.

## Key types

- [`ForemanServices`](Sources/ForemanServices.swift) – the root. Assembles
  and owns everything below, loads the configuration in `init` (a corrupt
  file keeps defaults *unsaved* and surfaces on `issueMessage`), runs launch
  restore (`start()` → `Repo.startIfEnabled()`), and owns the two funnels:
  persisted mutations (repo toggles/options, settings) **write through into
  the retained `ForemanConfiguration`** and save; every `Worker` transition
  recomputes the sleep assertion over the whole tree (draining workers
  included). Tree-level failures (config load, scan, save) land on the
  observable `issueMessage`; per-repo failures live on each repo's worker.
- [`Repo`](Sources/Repo.swift) – one repository in the tree: identity
  (`RepoID` = canonical absolute path, `name`, `rootURL`), the persisted
  intent (`isEnabled`, `isFavorite`, `options` — all `didSet`-guarded and
  funneled to the root), and its `Worker`. `isFavorite` is pure sidebar-
  ordering metadata with **no** worker side effect (only persistence), unlike
  `isEnabled`. **The toggle is declarative**: `isEnabled` records
  desired state, `worker.state` reports the actual one; a locate failure
  lands as `.failed` via `recordStartFailure` with the toggle still on, and
  switching a failed repo off acknowledges the failure (`Worker.stop()`
  settles a dead `.failed` to `.stopped`, so a disabled row never reads red).
  Transient intents that don't touch desired state: `startIfEnabled()`
  (launch restore), `retry()` (enabled + `.failed` only), `restart()`
  (`.running` only — resolves the executable *before* stopping so a locate
  failure never kills a working process, then rides the queued-restart
  machinery to respawn with the current options).
- [`Worker`](Sources/Worker.swift) – per-repo process owner. State is the
  single `State` enum (`stopped` / `running(pid:since:)` /
  `stopping(restartPending:)` / `failed(reason:)` — no `.starting`: spawning
  is synchronous on the main actor, so an in-between state would be
  unobservable); the private `Handle` carries the `Process`, its log
  `FileHandle`, and the `stopRequested` bit that turns a SIGTERM death into
  `.stopped` instead of `.failed`. Output appends to
  `<logDirectory>/<repo name>.log` with start/exit markers. `start` doesn't
  throw — a spawn failure lands in `.failed` and the log, so the state *is*
  the caller-observable result. The injected `onStateChange` fires once per
  real transition (never for same-value writes).
- [`RepoDiscovery`](Sources/RepoDiscovery.swift) – the stateful "many repos"
  node: holds `repos`, and `rescan(in:)` **reuses existing `Repo` instances
  by id** (live workers survive a rescan), creates new ones via the injected
  factory, and stops + drains vanished repos (retained until their process
  exit lands, so bookkeeping and the sleep assertion stay honest). A repo
  whose directory reappears while its old worker drains is *resurrected*
  from the draining set, never rebuilt — one id must never own two
  processes (or two log-file writers); `retainedRepoIDs` includes draining
  ids so the configuration prune can't strand a resurrected repo. The pure
  listing is the static `scan(_:)`: one directory level, subdirectories with
  a `.git` entry (directory or file, so worktrees/submodules count), hidden
  entries skipped, case-insensitive sort, **throws** when the directory
  can't be listed — and a failed rescan keeps the existing repos.
  `ScannedRepo` is the pre-tree value (name + root + `RepoID`).
- [`AppSettings`](Sources/AppSettings.swift) – observable global settings
  (`scanDirectory` / `agentExecutable`, with `resolvedScanDirectory`
  defaulting to `~/Development`). `didSet`-guarded; reports *which* property
  changed so the root persists always but rescans only for scan-directory
  changes.
- [`WorkerOptions`](Sources/WorkerOptions.swift) – Codable per-repo flags.
  `Assignment` is a single enum (`.shared` / `.pool(name:)`) so pool
  registration and pool name can't drift apart; labels are a named `Label`
  struct, not tuples. `arguments(workerDirectory:)` is the **only** place that
  spells CLI flags: worker-level flags before the `start` subcommand,
  `--verbose` after it.
- [`RepoConfiguration` / `ForemanConfiguration` / `WorkerConfigStore`](Sources/WorkerConfigStore.swift)
  – the persisted state and its JSON store. `RepoConfiguration` is the
  **single per-repo record** (`isEnabled`, `isFavorite`, `options`) — one
  struct rather than parallel maps keyed by `RepoID`, so the flags and options
  can't drift apart; `ForemanConfiguration` holds `scanDirectory`,
  `agentExecutable`, and `repos: [RepoID: RepoConfiguration]`. A repo whose
  record equals `RepoConfiguration.standard` (disabled, unfavorited, standard
  options) has no entry — absence reads identically, so the persistence funnel
  drops it. `load()` distinguishes *missing* (first launch → `.initial`) from
  *corrupt* (throws); don't collapse the two. `prune(discovered:under:)` drops
  `repos` entries for repos gone from the scan directory but must keep entries
  *outside* it — they're another scan directory's history (the prefix check
  appends "/" so a sibling like `~/CodeArchive` doesn't match a `~/Code` scan
  directory).
- [`RepoSection`](Sources/RepoSection.swift) – the pure sidebar ordering rule:
  `sections(from:)` splits the discovered repos into an `.enabled` section on
  top and a `.disabled` section below, floating favorites to the top of each
  (stable, so the name-sorted input order is otherwise preserved) and omitting
  an empty section. Lives in Core (not the view) so the ordering is
  unit-tested; the `Kind` carries no display text — section titles are the
  view's concern.
- [`LogTailReader`](Sources/LogTailReader.swift) – `tail(of:maxBytes:)` reads
  the end of a worker log file for display. `nil` means *no file yet* (a
  never-started worker — legitimate, not an error); other I/O failures
  throw. Truncated reads drop the partial first line so output starts on a
  line boundary.
- [`SleepInhibitor`](Sources/SleepInhibitor.swift) – idempotent wrapper around
  `ProcessInfo.beginActivity(.idleSystemSleepDisabled)`. The root recomputes
  it on every `Worker.onStateChange`, so the assertion is held exactly while
  ≥1 worker is live. The assertion itself sits behind the
  `SleepAssertionBackend` protocol (`@_spi(Testing)`); the testing init
  injects a conforming recorder instead of the real `ProcessInfo` backend.
- [`CursorAgentLocator`](Sources/CursorAgentLocator.swift) – resolves the
  executable from known install paths (GUI apps don't inherit shell `PATH`).
  An explicit configured path is *validated*, and a stale one throws rather
  than silently falling back to auto-locate.
- [`ForemanLog`](Sources/ForemanLog.swift) – LogKit facade, subsystem
  `com.stuff.foreman`, typed `Category` enum. Add a case to introduce a new
  category; never log with raw strings.

## Invariants & behaviors to preserve

- **The configuration is a retained backing store, not a projection.** Tree
  mutations write through into `ForemanConfiguration`; never rebuild it from
  the tree on save — entries belonging to *other* scan directories aren't in
  the tree and would be silently dropped.
- **Rescans reuse `Repo` instances by id.** A rescan must not replace the
  `Repo` (and thus kill or orphan its `Worker`) for a repo that's still
  there; vanished repos are stopped and drained, not dropped mid-exit, and
  a reappearing directory resurrects its draining `Repo` so a single id
  can never have two live processes.
- **Absence vs failure.** A repo with no persisted entry reads as
  `RepoConfiguration.standard` (disabled, unfavorited, `WorkerOptions.standard`
  — expected absence); an unreadable or undecodable config file throws (real
  failure). Keep that split — no `try?` or silent resets.
- **CLI defaults are deferred to, not duplicated.** An empty pool name or zero
  idle timeout omits the flag so the CLI's own default applies; don't bake the
  CLI's default values into rendered argv.
- **`RepoID` everywhere.** Config maps and repo lookups key by `RepoID`;
  never key by display name or raw path strings.
- **The toggle is declarative; transient intents don't touch it.** `isEnabled`
  is the single persisted desired state (restored at launch). `retry()` and
  `restart()` respawn without flipping it — don't reintroduce
  switch-reverting on failure; off-then-on (or Retry) is the retry.
- **Stop intent decides the end state.** A worker that dies after `stop()`
  reads as `.stopped` (SIGTERM kills the CLI by signal, but the user asked
  for it); an *unrequested* death is `.failed` with the exit code or signal
  in the reason. Don't collapse the two.
- **A start during `.stopping` queues exactly one restart.** The old process
  isn't gone yet, so the worker records a `PendingStart` (arguments captured
  at request time), flips the state to `.stopping(restartPending: true)`,
  and replays it when the exit lands. A `stop` in that window cancels the
  queue. Never silently drop a start — that's how the
  toggle-on-while-stopping bug read as "enabled but dead".
- **The sleep assertion tracks liveness, not toggles.** It's recomputed on
  every worker transition — held while any worker in the tree is live
  (draining ones included), released when the last one ends, never taken
  per-worker.

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
