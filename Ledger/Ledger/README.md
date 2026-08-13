# Ledger

A macOS **menu bar app** that shows your current-cycle Cursor spend at a glance.
The status item displays the cycle-to-date dollar amount.
Clicking it opens a popover with this cycle's spend, the included-usage breakdown, your plan, and the top models by usage.

All behavior lives in [`LedgerCore`](../LedgerCore).
This target is the thin SwiftUI/AppKit shell.

## Running

```bash
./ide --no-open              # regenerate the Xcode project
mise exec -- tuist build Ledger
```

Or run the `Ledger` scheme from Xcode.
The app lives in the menu bar (showing the current-cycle amount once loaded) and shows no Dock icon (`LSUIElement`).
It keeps running until you quit it from the popover.

### Install to /Applications

To run it standalone (no Xcode), use the install script.
It builds a Release build, installs it to `/Applications`, and launches it:

```bash
Ledger/install            # build, install to /Applications, and launch
Ledger/install --no-open  # build and install without launching
Ledger/install --dry-run  # describe the operation without changing anything
```

The app is ad-hoc code-signed (no Apple Developer account needed) and built locally (no Gatekeeper quarantine).
Re-run it to update your installed copy.
It stops only the exact installed executable.
It stages the complete replacement next to the destination.
It restores the prior app if that replacement fails.

## Setup

If you are signed in to the Cursor app, **there is nothing to configure**.
Ledger auto-detects your session from Cursor's local state.
The Account pane shows "Using your signed-in Cursor session".

If auto-detect cannot find a session (or it expired), paste a token in **Settings › Account**.
On `cursor.com`, open DevTools › Application › Cookies.
Copy `WorkosCursorSessionToken` and paste it.
It is stored in your Keychain and overrides auto-detect until you clear it.

The **General** pane has *Launch Ledger at login* (via `SMAppService`), with a shortcut to System Settings if macOS needs you to approve the login item.

## What it shows

- **Menu-bar title** — the current billing cycle's usage-based spend, refreshed automatically every 5 minutes (configurable in Settings › General).
  Opening the popover shows the latest fetched state.
  It does not trigger a network request.
- **Popover** — this cycle's spend and date range, **today** and **this week** spend (differenced from locally recorded history — hidden until enough exists), your plan tier, an **included usage** as two side-by-side bars (first-party/Auto and third-party/API — a single blended figure would hide that one pool can be maxed while the other is barely used), **top models this cycle** as usage shares (each model ≥5% gets its own bar.
  Smaller ones roll into a single multi-colored "Other models" bar with a legend), and when it last updated.
  A **Refresh** button forces an immediate fetch (including the model breakdown, which the automatic refresh only re-walks every 15 minutes since it costs several requests).
  If a refresh fails (e.g. you go offline) the last figures stay on screen and the "Updated…" caption turns into an amber stale warning rather than blanking.
  The full error screen (with a shortcut to Settings) shows only before anything has loaded — no session yet, an expired session, or a first-load network failure.

There is no year-to-date total by design.
The monthly-invoice endpoint is a billing ledger with cross-month credit/adjustment lines.
Summing it is not a meaningful "spend this year" (see `LedgerCore`'s README).

The per-model rows are shown as **relative shares**, not dollars.
Their summed cost (from `get-filtered-usage-events`) is total usage value — more than the billed on-demand headline (by the included allowance).
Showing dollars alongside the headline would look like they do not add up.

## Design notes

- The status item and popover are **AppKit** (`NSStatusItem` + `NSPopover`), not `MenuBarExtra`.
  The menu-bar title mirrors observable model state via an `Observations` loop, which the AppKit path drives reliably.
  (The old Foreman menu-bar app landed on the same pattern for the same reason.)
- Data comes from Cursor's **undocumented dashboard API** (the same endpoints the website calls).
  It can change without notice.

## Limitations

- Reuses your Cursor **web session**.
  When it expires you re-open Cursor (or paste a fresh token).
- On a plan with usage-based pricing off, the `$` figures reflect the value of included compute, not money owed.
