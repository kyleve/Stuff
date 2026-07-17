# LedgerCore

The model layer for the **Ledger** menu bar app: it fetches your current
Cursor billing-cycle spend from the Cursor **Admin API** and reduces it to the
single team member you're signed in as. The SwiftUI/AppKit shell lives in the
[`Ledger`](../Ledger) app target and binds this tree directly.

## What it does

- Calls `POST https://api.cursor.com/teams/spend` (HTTP Basic auth, the Admin
  API key as the username and an empty password — the same shape as `curl -u
  YOUR_API_KEY:`).
- Filters the team response down to the member whose email you configured
  (case-insensitively).
- Exposes one observable `LoadState` (`idle` / `loading` / `loaded(MemberSpend)`
  / `failed(LoadError)`) so the UI can never show a half-loaded mix of value,
  spinner, and error.

Only the **current billing cycle** is available from the API — there is no
per-user historical endpoint, and LedgerCore keeps no local history.

## Public API

- `LedgerServices` — the `@MainActor @Observable` root. Owns the settings,
  Keychain, spend provider, and login item. Key surface: `loadState`,
  `lastUpdated`, `hasAPIKey`, `settings`, `startsAtLogin`, `refresh()`,
  `setAPIKey(_:)` / `clearAPIKey()`, `start()` / `stop()`.
- `LedgerSettings` — the observable settings node (`teamMemberEmail`,
  `refreshInterval`); mutations funnel to the tree, which persists them.
- `LedgerConfiguration` / `LedgerConfigStore` — the persisted JSON
  (`~/Library/Application Support/com.stuff.ledger/configuration.json`). The
  email and refresh interval only — **never** the API key.
- `KeychainStore` (protocol) + `SystemKeychainStore` — the Admin API key lives
  in the login Keychain, not the JSON.
- `SpendProvider` (protocol) + `CursorSpendAPI` — the network seam.
- `Spend` types — `SpendResponse` / `MemberSpend`, with a `totalCents` that
  prefers the API's `overallSpendCents` and falls back to on-demand + included.
- `LoginItemController` — launch-at-login via `SMAppService`.
- `LedgerLog` — the LogKit logging facade (subsystem `com.stuff.ledger`).

## How spend is computed

`MemberSpend.totalCents` prefers `overallSpendCents` when the API returns it,
otherwise sums `spendCents` (on-demand overage) and `includedSpendCents`
(allowance usage). Cent fields are `Double`: the Admin API added sub-cent
precision on 2026-06-04 so results reconcile with invoices.

## Credentials

Create an Admin API key in the Cursor dashboard. It's stored in the Keychain
(`SystemKeychainStore`); tests and previews swap in `InMemoryKeychainStore`.
Ledger isn't sandboxed, so it reaches the login Keychain without a
keychain-access-group entitlement.

## Testing

Swift Testing in [`Tests/`](Tests), hostless on macOS (`tuist test
LedgerCoreTests -- -destination 'platform=macOS'`). Network and Keychain are
behind protocol seams, so `ScriptedSpendProvider` and `InMemoryKeychainStore`
(both `@_spi(Testing)`, DEBUG-only) drive the suites without real HTTP or
Keychain access.
