# Foreman (app target) – Module Shape

The SwiftUI shell for the Foreman menu bar app: an AppKit status item that
toggles a regular window, a thin session facade, and the window's views (a
`NavigationSplitView`). Domain behavior — the observable model tree
(`ForemanServices` → `AppSettings` + `RepoDiscovery` → `Repo` → `Worker`),
config persistence, the sleep assertion — lives in
[`ForemanCore`](../ForemanCore); views bind the Core objects directly and
this target only renders and routes. See [`README.md`](README.md) for the
narrative.

This file complements the root [`AGENTS.md`](../../AGENTS.md) (build system,
formatting, global conventions) and ForemanCore's
[`AGENTS.md`](../ForemanCore/AGENTS.md) (core invariants). Read those first.

## Shape

- [`ForemanApp` / `AppDelegate`](Sources/ForemanApp.swift) – `@main` app whose
  only SwiftUI scene is `Settings` hosting `SettingsView` (reached via the
  app menu / Cmd-, in the regular-app phase, or the toolbar `SettingsLink`);
  the rest of the UI is AppKit-managed by
  `AppDelegate`, whose status-item icon swaps `hammer`/`hammer.fill` on
  worker liveness. It starts the session on launch and calls
  `stopAllWorkers()` in `applicationWillTerminate` — the **stop-on-quit
  lifecycle**: Foreman owns its worker processes and must never leave
  orphans. The target is an `LSUIElement` with a hand-written Info.plist in
  [`Project.swift`](../../Project.swift) (don't switch it to
  `.extendingDefault`, which injects `NSMainStoryboardFile` on macOS).
- [`ForemanSession`](Sources/ForemanSession.swift) – a deliberately thin
  facade: owns the `ForemanServices` root, forwards the app-level intents
  (`start`, `rescan`, `stopAllWorkers`), and re-exposes `repos`, `settings`,
  `issueMessage`, and the liveness flags. There is no mirroring layer —
  views bind the Core `Repo` objects directly (`$repo.isEnabled`,
  `repo.worker.state`), and toggle/options/settings semantics (declarative
  toggle, persistence funnel, retry/restart intents) live in ForemanCore;
  see [its AGENTS.md](../ForemanCore/AGENTS.md). If session logic grows
  beyond forwarding, move it into Core.
- **The status item is AppKit (`NSStatusItem` + a regular `NSWindow`), not
  `MenuBarExtra`, on purpose.** `MenuBarExtra(.window)` built its content
  once at launch and lost SwiftUI observation of it: `@Observable` mutations
  landing while the panel was closed never rendered ("empty list until you
  open settings"), and every open-detection hook tried — `onAppear`,
  `controlActiveState`, key-window and occlusion notifications, an
  observation pump into `@State` — failed to fire or failed to render.
  The delegate owns a persistent, resizable window (frame autosaved as
  `ForemanMain`, `isReleasedWhenClosed = false` since we reuse it); the
  status-item click toggles it, closing it just hides it, and
  `windowDidBecomeKey` — reliable for regular windows — drives the
  rescan-on-open. **Key focus needs the activation-policy dance**:
  cooperative activation won't reliably focus an accessory app's window, so
  `showWindow` promotes the app to `.regular` (Dock icon appears while the
  window is up) and hiding/closing reverts to `.accessory` after a short
  delay (an immediate flip glitches the menu bar). The status-item icon is
  plain AppKit driven by a `for await` loop over the stdlib `Observations`
  sequence on `isAnyWorkerLive`. Don't migrate back to `MenuBarExtra`
  without re-verifying all of the above.
- [`MainWindowView`](Sources/MainWindowView.swift) – the window content: a
  `NavigationSplitView` with repo rows in the sidebar and the selected
  worker's detail on the right, plus the toolbar (sleep badge, Rescan, a
  `SettingsLink`, Quit) and the issue banner. The detail carries
  `.id(repo.id)` so per-repo `@State` (options draft, log tail) resets on
  selection change. `onAppear` covers the first-open scan; later opens
  rescan via the window delegate (no file watching).
- [`WorkerRowView`](Sources/WorkerRowView.swift) – sidebar row: status dot,
  name (+ a red "failed" hint), toggle. Actions and details live in the
  detail pane.
- [`WorkerDetailView`](Sources/WorkerDetailView.swift) – one worker's
  status/pid/uptime (uptime renders live via `Text(_, style: .relative)`),
  the exact command the next start will spawn, the inline options editor,
  and the log tail. The status row carries the contextual transient
  controls: **Retry** for an enabled repo in `.failed`, **Restart** while
  `.running` — both call the `Repo` intents (no view-local process logic)
  and never touch the persisted toggle. Start/Stop as user actions stay the
  enable toggle.
- [`WorkerLogView`](Sources/WorkerLogView.swift) – tails the worker's log
  file via `LogTailReader`, polling once a second while visible. One `Tail`
  enum so "no file yet", content, and a read failure can't coexist; polls
  that read the same content don't write `@State` (a redundant write per
  second would wipe text selection). **Hiding the window does not cancel
  `.task`** — an ordered-out `NSWindow` keeps its SwiftUI hierarchy alive
  and loops keep ticking (verified empirically) — so the poll is also gated
  on [`WindowVisibilityReader`](Sources/WindowVisibilityReader.swift), which
  reports the hosting window's occlusion state into a binding. Any future
  periodic work in this window needs the same gate.
- [`WorkerOptionsView`](Sources/WorkerOptionsView.swift) – editor over a
  local `@State` draft, written back to `repo.options` on Save (Core
  persists). The draft reshapes `WorkerOptions` for binding (optionals ↔
  empty strings, the pool case ↔ toggle + name); conversion lives in the
  draft type, not scattered through the form. It is a `Section` embedded in
  the detail form, locked while the worker is live: options apply at spawn,
  so mid-run edits would silently do nothing until a restart.
- [`SettingsView`](Sources/SettingsView.swift) – lives in the `Settings`
  scene, so it follows settings-window conventions: fields apply on commit
  (Return / focus loss / panel selection) with no Save button, written to
  the observable `AppSettings` (Core persists and rescans). The window
  keeps its hierarchy across opens, so the field drafts are re-seeded from
  the settings when the window becomes visible (`WindowVisibilityReader` —
  same caveat as the log view).
- [`PreviewSupport`](Sources/PreviewSupport.swift) – DEBUG-only fixtures
  (`emptySession()`, `populatedSession()`) backed by throwaway temp
  directories; previews never read the real config, spawn processes, or touch
  `~/Development`.

## Conventions

- Follow the root rules: exhaustive `switch`, no closure `Binding(get:set:)`
  in views, core behavior goes to `ForemanCore` (this target should stay
  view + view-model only).
- Feature-level todos live in [`../TODOs.md`](../TODOs.md) (mirrors
  [`Where/TODOs.md`](../../Where/TODOs.md)): tag entries with conventional
  commit semantics (`feat:`, `fix:`, …), file them under the priority
  sections, and move finished ones to "Completed issues" instead of
  deleting them.
- Every previewable view ships a `#Preview` using `PreviewSupport` fixtures.
- New worker CLI flags: add the field + argv rendering to
  `WorkerOptions` in ForemanCore first (with tests), then surface it in
  `WorkerOptionsView`'s draft.

## Testing

The app target has no test bundle; behavior belongs in ForemanCore where
`ForemanCoreTests` covers it (run `tuist test ForemanCoreTests -- -destination
'platform=macOS'`). If session logic grows beyond thin orchestration, move it
into ForemanCore rather than adding view-model tests here.
