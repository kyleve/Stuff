# ForemanCore – Module Shape

ForemanCore is the model layer for the Foreman menu bar app: a tree of
`@MainActor @Observable` objects rooted in `ForemanServices`, plus the value
types they persist and the logging facade (`ForemanLog`, typed categories).
The SwiftUI layer lives in the app target ([`Foreman/Foreman`](../Foreman))
and binds the tree directly; see [`README.md`](README.md) for the narrative
and per-type detail.

```
ForemanServices ── AppSettings
       ├────────── RepoDiscovery ── [Repo] ── Worker
       ├────────── WorkerConfigStore (ForemanConfiguration JSON)
       ├────────── SleepInhibitor
       ├────────── LoginItemController (SMAppService)
       └────────── RepoCopyRemoving (worktree remove / trash clone)
```

The MCP-facing control surface (`ControlRequest`/`ControlResponse`,
`ControlRequestHandler`, `ControlConnection`'s wire framing + dispatch, the
`describe`/`adopt`/`removeCopy` intents, and `CopyProvenance`) is
transport-agnostic and lives here so it's testable over a `socketpair`; the app
target owns only the listening socket, accept loop, and threading (see [the app
AGENTS](../Foreman/AGENTS.md)). The TypeScript client in
[`foreman-mcp`](../foreman-mcp) mirrors the wire types.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + Observation + LogKit only.** No SwiftUI, no AppKit UI —
  views and the thin session facade belong to the app target. ForemanCore is
  the repo's only macOS-only package library (`.macOS(.v26)` in
  [`Package.swift`](../../Package.swift)).
- The hostless macOS test bundle `ForemanCoreTests` is declared directly in
  [`Project.swift`](../../Project.swift) and runs via the
  `Foreman-macOS-Tests` scheme.

## Invariants

- **The configuration is a retained backing store, not a projection.** Tree
  mutations write through into `ForemanConfiguration` and save; never rebuild
  it from the tree — entries belonging to *other* scan directories aren't in
  the tree and would be silently dropped.
- **Rescans reuse `Repo` instances by id** (live workers survive a rescan);
  vanished repos are stopped and drained, not dropped mid-exit, and a
  reappearing directory resurrects its draining `Repo` — one id must never
  own two processes.
- **The toggle is declarative.** `isEnabled` is the single persisted desired
  state; `worker.state` reports the actual one. Transient intents (`retry()`,
  `restart()`, `startIfEnabled()`) never flip it, and failures don't revert
  it.
- **Stop intent decides the end state.** A death after `stop()` reads as
  `.stopped`; an unrequested death is `.failed` with the reason. Don't
  collapse the two.
- **A start during `.stopping` queues exactly one restart**, replayed when
  the exit lands (a `stop` in that window cancels it). Never silently drop a
  start.
- **The sleep assertion tracks liveness, not toggles** — recomputed on every
  worker transition, held while any worker (draining included) is live.
- **The login item is OS-owned, not persisted config.** `LoginItemController`
  reads/writes `SMAppService.mainApp` (behind an `@_spi(Testing)` backend) as a
  typed `LoginItemStatus`; `requiresApproval` counts as *on* (registered but
  pending), so it never reads as off. `ForemanServices.startsAtLogin` is a live
  read of that status, and its setter surfaces failures on the dedicated
  `loginItemError` (the toggle lives in the settings window, not the main
  banner) while keeping the observed value honest. Never mirror it into
  `ForemanConfiguration` — the system is the source of truth. Launch-at-login
  just relaunches the app, which reuses the existing `start()` restore of
  enabled workers.
- **Copies are Foreman's to own.** `removeCopy(at:)` only acts on a repo with
  recorded `CopyProvenance` (throwing `ControlError.notACopy` otherwise) and
  always stops + drains the worker *before* touching the filesystem — never
  remove a copy out from under a live process. `adoptAndStartWorker` rejects a
  path that isn't a direct child of the scan directory. The removal itself goes
  through the injected `RepoCopyRemoving` so tests never trash real files. The
  wire types (`ControlRequest`/`ControlResponse` and their DTOs) are the
  contract with `foreman-mcp`'s `src/control.ts` — change both together.
- **Absence vs failure.** Missing options read as `WorkerOptions.standard`
  and a missing config file is `.initial`; an unreadable/undecodable file
  throws. **CLI defaults are deferred to, not duplicated** — omit a flag
  rather than baking the CLI's default into argv (`WorkerOptions.arguments`
  is the only place that spells flags). **`RepoID` everywhere** — never key
  by display name or raw path strings.

## Localization

User-facing strings (worker failure reasons in `Worker`, the scan/save/login
errors and config-load fallback in `ForemanServices`,
`CursorAgentLocator.NotFoundError`, and the `ControlError` messages surfaced
back to the MCP) resolve through Xcode 26 **generated
symbols** against [`Sources/Resources/Localizable.xcstrings`](Sources/Resources/Localizable.xcstrings)
(a processed resource in [`Package.swift`](../../Package.swift)) — used as
`String(localized: .workerExitedWithCode(code: …))` etc. The symbol already
carries the module bundle, so there is no `bundle: .module`. Add the key to the
catalog first; interpolated strings use named placeholders (`%(code)lld`,
`%(error)@`).

- **The `en` catalog value is the source of truth** for tests that assert exact
  reason/message text (e.g. `"Exited with code 3"`, `"Couldn't read saved
  settings — using defaults."`) — keep them byte-for-byte when editing.
- Symbol generation runs under both the Tuist / `xcodebuild` flow **and** a plain
  `swift build` (the Swift 6.2 toolchain builds SwiftPM targets with the Swift
  Build engine, which processes the catalog into
  `GeneratedStringSymbols_Localizable.swift`), so the module compiles either way.

## Testing

Swift Testing in [`Tests/`](Tests), hostless on macOS (`tuist test
ForemanCoreTests -- -destination 'platform=macOS'`). Shared fixtures live in
[`ForemanCoreTestSupport.swift`](Tests/ForemanCoreTestSupport.swift);
filesystem tests use unique temp directories and never touch the user's
`~/Development` or Application Support.
