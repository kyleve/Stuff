# Foreman (app target) – Module Shape

The SwiftUI shell for the Foreman menu bar app: a `MenuBarExtra` scene, an
`@Observable` session view-model, and the menu's views. Domain behavior —
repo discovery, worker process supervision, config persistence, the sleep
assertion — lives in [`ForemanCore`](../ForemanCore); this target only
orchestrates and renders it. See [`README.md`](README.md) for the narrative.

This file complements the root [`AGENTS.md`](../../AGENTS.md) (build system,
formatting, global conventions) and ForemanCore's
[`AGENTS.md`](../ForemanCore/AGENTS.md) (core invariants). Read those first.

## Shape

- [`ForemanApp`](Sources/ForemanApp.swift) – `@main` `MenuBarExtra`
  (`.window` style) whose label swaps `hammer`/`hammer.fill` on worker
  liveness. `AppDelegate` starts the session on launch and calls
  `stopAllWorkers()` in `applicationWillTerminate` — the **stop-on-quit
  lifecycle**: Foreman owns its worker processes and must never leave
  orphans. The target is an `LSUIElement` with a hand-written Info.plist in
  [`Project.swift`](../../Project.swift) (don't switch it to
  `.extendingDefault`, which injects `NSMainStoryboardFile` on macOS).
- [`ForemanSession`](Sources/ForemanSession.swift) – the view model. Mirrors
  `WorkerSupervisor` state into `WorkerRow`s (an `@Observable` row per repo so
  `Toggle` binds to `$row.isEnabled` — no closure-built `Binding`s, per root
  rules), exposes intents (`rescan`, `updateOptions`, `setScanDirectory`,
  `setAgentExecutable`), and persists through `WorkerConfigStore` after every
  change. `start()` restores the config and restarts previously-enabled
  workers. Failures (unreadable config, failed scan, missing `cursor-agent`,
  failed save) land in the observable `issueMessage` *and* the log — honest
  state, never a silent default.
- [`MenuContentView`](Sources/MenuContentView.swift) – the window. One
  `Screen` enum (`list` / `options(row)` / `settings`) keeps exactly one
  surface visible. `onAppear` rescans, so the list is fresh every time the
  status item opens (no file watching).
- [`WorkerRowView`](Sources/WorkerRowView.swift) – status dot + toggle +
  open-log + options. The options button is disabled while the worker is
  live: options apply at spawn, so editing them mid-run would silently do
  nothing until a restart.
- [`WorkerOptionsView`](Sources/WorkerOptionsView.swift) /
  [`SettingsView`](Sources/SettingsView.swift) – form editors over a local
  `@State` draft, written back through session intents on Save. The draft
  reshapes `WorkerOptions` for binding (optionals ↔ empty strings, the pool
  case ↔ toggle + name); conversion lives in the draft type, not scattered
  through the form.
- [`PreviewSupport`](Sources/PreviewSupport.swift) – DEBUG-only fixtures
  (`emptySession()`, `populatedSession()`) backed by throwaway temp
  directories; previews never read the real config, spawn processes, or touch
  `~/Development`.

## Conventions

- Follow the root rules: exhaustive `switch`, no closure `Binding(get:set:)`
  in views, core behavior goes to `ForemanCore` (this target should stay
  view + view-model only).
- Every previewable view ships a `#Preview` using `PreviewSupport` fixtures.
- New worker CLI flags: add the field + argv rendering to
  `WorkerOptions` in ForemanCore first (with tests), then surface it in
  `WorkerOptionsView`'s draft.

## Testing

The app target has no test bundle; behavior belongs in ForemanCore where
`ForemanCoreTests` covers it (run `tuist test ForemanCoreTests -- -destination
'platform=macOS'`). If session logic grows beyond thin orchestration, move it
into ForemanCore rather than adding view-model tests here.
