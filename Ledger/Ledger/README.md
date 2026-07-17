# Ledger

A macOS **menu bar app** that shows your current-cycle Cursor spend at a
glance. The status item displays the cycle-to-date dollar amount; clicking it
opens a popover with the breakdown (included usage, on-demand, usage-based
requests) and a Refresh button.

All behavior lives in [`LedgerCore`](../LedgerCore); this target is the thin
SwiftUI/AppKit shell.

## Running

```bash
./ide --no-open              # regenerate the Xcode project
mise exec -- tuist build Ledger
```

or run the `Ledger` scheme from Xcode. The app lives in the menu bar (a
dollar-sign icon with the amount beside it once loaded) and shows no Dock icon
(`LSUIElement`). It keeps running until you quit it from the popover.

## Setup

Open **Settings** (the gear in the popover, or Cmd-,) and fill in the
**Account** pane:

- **Team member email** — the member of your Cursor team whose spend to show.
- **Admin API key** — created in the Cursor dashboard (Admin API). It's stored
  in your **Keychain**, never on disk in plaintext.

The **General** pane has *Launch Ledger at login* (via `SMAppService`); if
macOS needs you to approve the login item, the pane links straight to System
Settings.

## What it shows

- **Menu-bar title** — the current billing cycle's total spend, updated
  automatically (every 15 minutes) and whenever you open the popover.
- **Popover** — the cycle total, an included-usage / on-demand breakdown, the
  usage-based request count, and when it last updated. On an error (missing
  credentials, unknown email, a rejected key, a network failure) it explains
  what to fix and offers a shortcut to Settings.

## Design notes

- The status item and popover are **AppKit** (`NSStatusItem` + `NSPopover`),
  not `MenuBarExtra`: the menu-bar title mirrors observable model state via an
  `Observations` loop, which the AppKit path drives reliably. (The old Foreman
  menu-bar app landed on the same pattern for the same reason.)
- **Only the current cycle** is shown — the Cursor Admin API exposes no
  per-user historical spend, and Ledger keeps no local history.

## Limitations

- Requires a Cursor **Admin API key**, which is a team/enterprise capability.
- The Admin API returns spend for the **current billing cycle only**.
