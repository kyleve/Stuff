# Foreman (app target) – Module Shape

The SwiftUI shell for the Foreman menu bar app: an AppKit status item that
toggles a regular window (`NavigationSplitView` of repo rows + worker detail),
a thin `ForemanSession` facade, and a `Settings` scene. See
[`README.md`](README.md) for the narrative.

This file complements the root [`AGENTS.md`](../../AGENTS.md) (build system,
formatting, global conventions) and ForemanCore's
[`AGENTS.md`](../ForemanCore/AGENTS.md) (core invariants). Read those first.

## Scope & rules

- **Thin shell only.** Domain behavior — the observable model tree, config
  persistence, the sleep assertion — lives in [`ForemanCore`](../ForemanCore).
  There is no mirroring layer: views bind Core `Repo` objects directly
  (`$repo.isEnabled`, `repo.worker.state`), and `ForemanSession` only forwards
  app-level intents. If session logic grows beyond forwarding, move it into
  Core.
- **Stop-on-quit lifecycle.** The app delegate calls `stopAllWorkers()` in
  `applicationWillTerminate` — Foreman owns its worker processes and must
  never leave orphans.
- **The control socket lives here, the protocol doesn't.** `ControlServer` is
  the only socket-owning code (raw POSIX unix-domain socket, JSON-lines); it
  decodes a line, calls `ControlRequestHandler` **on the main actor**, and
  encodes the reply. Started in `applicationDidFinishLaunching` and torn down in
  `applicationWillTerminate`, both via `ForemanSession`
  (`startControlServer()` / `stopControlServer()`). All request→intent mapping
  belongs in ForemanCore's `ControlRequestHandler`, not here. The Remove-copy UI
  action goes through `ForemanSession.removeCopy(_:)`, which surfaces failures on
  `actionError` (an alert) rather than throwing into a view; copy provenance for
  the sidebar badge / detail is presented via `CopyProvenanceDisplay`.
- New worker CLI flags start in ForemanCore (`WorkerOptions` field + argv
  rendering, with tests), then surface in `WorkerOptionsView`'s draft.
- Feature-level todos live in [`../TODOs.md`](../TODOs.md) (conventional
  commit tags, priority sections, finished items move to "Completed issues").
- Every previewable view ships a `#Preview` using `PreviewSupport` fixtures
  (temp-directory backed; never the real config or `~/Development`).

## Localization

All user-facing copy lives in
[`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings) and is
referenced through Xcode 26's **generated symbols** (the
`STRING_CATALOG_GENERATE_SYMBOLS` build setting, set on the target in
[`Project.swift`](../../Project.swift)) — e.g. `Text(.toolbarRescan)`,
`Button(.commonSave)`, `.help(.toolbarRescanHelp)`,
`Text(.statusFailedReason(reason: …))`. There is **no** hand-written `Strings`
enum (unlike WhereUI). Add the key to the catalog first (a manual entry with a
stable dotted key like `toolbar.rescan`), then reference the generated symbol;
a missing key is a compile error. Interpolated strings use named placeholders
(`%(pid)lld`, `%(message)@`) so the symbol is a function with typed arguments.

Proper nouns stay literal — the app name **"Foreman"** (`navigationTitle`,
`NSWindow.title`, the icon's accessibility description) and the **"cursor-agent"**
CLI name. Dynamic data (repo names, paths, pids, upstream
`error.localizedDescription`, the command preview) is passed as arguments into
placeholder symbols, never added as catalog keys.

## Hard-won platform lessons (don't undo)

- **The status item is AppKit (`NSStatusItem` + a reused `NSWindow`), not
  `MenuBarExtra`, on purpose.** `MenuBarExtra(.window)` built its content once
  at launch and lost `@Observable` observation while the panel was closed, and
  every open-detection hook tried failed. The delegate's regular window gets
  reliable `windowDidBecomeKey` (drives rescan-on-open), and key focus needs
  the activation-policy dance (promote to `.regular` while visible, revert to
  `.accessory` after a short delay). Don't migrate back without re-verifying
  all of that.
- **Hiding the window does not cancel `.task`** — an ordered-out `NSWindow`
  keeps its SwiftUI hierarchy alive and loops keep ticking (verified
  empirically). Any periodic work in this window must gate on
  `WindowVisibilityReader` (see `WorkerLogView`), and the settings General
  pane re-reads the login-item status on visibility (see `SettingsView`). The
  settings path fields are edited in an explicit Save/Cancel sheet, so there
  is no commit-on-blur to lose when switching panes.
- The target is an `LSUIElement` with a hand-written Info.plist in
  [`Project.swift`](../../Project.swift) — don't switch to
  `.extendingDefault`, which injects `NSMainStoryboardFile` on macOS.

## Testing

The app target has no test bundle; behavior belongs in ForemanCore where
`ForemanCoreTests` covers it. If session logic grows beyond thin
orchestration, move it into Core rather than adding view-model tests here.
