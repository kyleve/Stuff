# Ledger – Module Shape

Ledger is the native-macOS menu bar app that displays your current-cycle Cursor
spend. It is a thin SwiftUI/AppKit shell over [`LedgerCore`](../LedgerCore),
which does all the fetching and modeling; see [`README.md`](README.md) for the
narrative.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Depends only on **LedgerCore** (plus SwiftUI/AppKit). It's the app target in
  [`Project.swift`](../../Project.swift) (`.mac` destination, `com.stuff.ledger`,
  `LSUIElement`), paired with the hostless `LedgerCoreTests` bundle in the same
  file and driven by the `Ledger` / `Ledger-macOS-Tests` schemes.
- No behavior lives here — persistence, networking, and domain rules are all in
  LedgerCore. This target renders `LoadState` and routes intents.

## Architecture

- `LedgerApp` + `AppDelegate` — the `NSStatusItem` + `NSPopover` shell. The
  status title mirrors `LedgerSession.statusTitle` through an `Observations`
  loop (deliberately AppKit, not `MenuBarExtra`). The SwiftUI `Settings` scene
  hosts `SettingsView`.
- `LedgerSession` — the thin `@Observable` facade over `LedgerServices`: views
  read its mirrored state and call its intent methods (`refresh`, `setAPIKey`,
  …); it owns the Core root.
- `SpendView` — the popover; renders the single `LoadState`.
- `SettingsView` — a System-Settings-style sidebar (General + Account panes).
- `CurrencyFormat` — the one place spend is formatted as USD.

## Invariants

- **The menu-bar title is driven by observation, not polling.** Keep the
  `Observations({ session.statusTitle })` loop as the update path; don't add a
  timer that reads the title.
- **Credentials commit explicitly.** The Account pane's email and API-key
  fields save on an explicit button, and the key goes straight to the Keychain
  via `session.setAPIKey` — never mirror it into `@AppStorage` or the config
  JSON.
- **No `Binding(get:set:)`.** Bind to the observable session/settings; use
  local `@State` drafts for the explicit-commit fields.

## Testing

The app target has no test bundle of its own — logic is tested in
`LedgerCoreTests`. `PreviewSupport` (DEBUG) builds sessions from
`ScriptedSpendProvider` + `InMemoryKeychainStore`, so previews never hit the
network or Keychain.
