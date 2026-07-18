# Ledger

A macOS **menu bar app** that shows your current-cycle Cursor spend at a
glance. The status item displays the cycle-to-date dollar amount; clicking it
opens a popover with this cycle's spend, a year-to-date total, the included-usage
breakdown, and your plan.

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

If you're signed in to the Cursor app, **there's nothing to configure** — Ledger
auto-detects your session from Cursor's local state. The Account pane shows
"Using your signed-in Cursor session".

If auto-detect can't find a session (or it expired), paste a token in
**Settings › Account**: on `cursor.com`, open DevTools › Application › Cookies,
copy `WorkosCursorSessionToken`, and paste it. It's stored in your Keychain and
overrides auto-detect until you clear it.

The **General** pane has *Launch Ledger at login* (via `SMAppService`), with a
shortcut to System Settings if macOS needs you to approve the login item.

## What it shows

- **Menu-bar title** — the current billing cycle's usage-based spend, refreshed
  automatically every 15 minutes. Opening the popover just shows the latest
  fetched state; it doesn't trigger a network request.
- **Popover** — this cycle's spend and date range, a **year-to-date** total,
  your plan tier, an **included-usage** progress bar (with Cursor's own status
  lines), **top models this cycle** as usage shares, and when it last updated. A
  **Refresh** button forces an immediate fetch. On an error (no session, an
  expired session, a network failure) it explains what to fix and offers a
  shortcut to Settings.

The per-model rows are shown as **relative shares**, not dollars: the dashboard's
per-model figure (`get-aggregated-usage-events`) measures compute differently
from the billed on-demand headline, so showing its dollars alongside the
headline would look like they don't add up.

## Design notes

- The status item and popover are **AppKit** (`NSStatusItem` + `NSPopover`), not
  `MenuBarExtra`: the menu-bar title mirrors observable model state via an
  `Observations` loop, which the AppKit path drives reliably. (The old Foreman
  menu-bar app landed on the same pattern for the same reason.)
- Data comes from Cursor's **undocumented dashboard API** (the same endpoints
  the website calls), so it can change without notice.

## Limitations

- Reuses your Cursor **web session**; when it expires you re-open Cursor (or
  paste a fresh token).
- On a plan with usage-based pricing off, the `$` figures reflect the value of
  included compute, not money owed.
