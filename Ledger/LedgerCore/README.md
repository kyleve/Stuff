# LedgerCore

The model layer for the **Ledger** menu bar app: it fetches your current
Cursor billing-cycle spend (and a year-to-date total) from the same
undocumented dashboard endpoints the `cursor.com/dashboard/usage` page uses,
authenticated with your Cursor **session token**. The SwiftUI/AppKit shell
lives in the [`Ledger`](../Ledger) app target and binds this tree directly.

## What it does

- Resolves a session token — **auto-detected** from your local Cursor app
  (`state.vscdb` → `cursorAuth/accessToken`), or a value you **paste** into
  Settings (stored in the Keychain, which overrides auto-detect).
- Calls `GET /api/usage-summary` for the current cycle's dates, plan type, and
  live usage-based spend, and `POST /api/dashboard/get-monthly-invoice` for each
  prior month of the year.
- Reduces it all to one observable `LoadState` (`idle` / `loading` /
  `loaded(SpendSnapshot)` / `failed(LoadError)`).

Works for **individual** accounts (no team/Admin API needed).

## Authentication

The dashboard uses WorkOS session cookies. The cookie value must be
`"<userId>::<jwt>"`; the Cursor app stores only the raw JWT, so
`SessionToken(rawToken:)` derives the `userId` from the JWT's `sub` claim
(`auth0|user_ABC` → `user_ABC`) and builds the cookie. A bare JWT is rejected
by the API (HTTP 401) — hence the prefix.

`CursorLocalTokenSource` reads Cursor's `state.vscdb` (a SQLite key-value store)
**read-only**. Nothing is written or locked; a missing file/key is simply "no
auto-token", surfaced as `LoadError.missingCredentials`.

## Public API

- `LedgerServices` — the `@MainActor @Observable` root: `loadState`,
  `lastUpdated`, `hasManualToken`, `autoTokenAvailable`, `settings`,
  `startsAtLogin`, `refresh()`, `setManualToken(_:)` / `clearManualToken()`,
  `start()` / `stop()`.
- `SessionToken` / `SessionTokenSource` / `CursorLocalTokenSource` — the auth
  seam.
- `DashboardProvider` + `CursorDashboardAPI` — the network seam.
- `UsageSummary`, `MonthlyInvoice`, `SpendSnapshot` — the wire + view models
  (cents are integers).
- `KeychainStore` / `SystemKeychainStore` — a pasted token's storage.
- `LedgerSettings` / `LedgerConfiguration` / `LedgerConfigStore` — the persisted
  refresh interval (no secrets).
- `LoginItemController` — launch-at-login via `SMAppService`.
- `LedgerLog` — the LogKit logging facade (subsystem `com.stuff.ledger`).

## How the figures are computed

- **This cycle** = `usage-summary` → `individualUsage.onDemand.used` (cents),
  the live usage-based spend.
- **This year** = the sum of the prior months' `get-monthly-invoice` totals plus
  the current cycle's live figure (the current month's invoice lags until
  charges post, so the live number stands in for it).

All money is cents. Note: on a plan with usage-based pricing off, these `$`
figures reflect included-compute value, not money owed.

## Testing

Swift Testing in [`Tests/`](Tests), hostless on macOS (`tuist test
LedgerCoreTests -- -destination 'platform=macOS'`). Shared fixtures live in
[`LedgerCoreTestSupport.swift`](Tests/LedgerCoreTestSupport.swift). The network,
token source, and Keychain are behind protocol seams, so `ScriptedDashboardProvider`,
`StubTokenSource`, and `InMemoryKeychainStore` (all `@_spi(Testing)`, DEBUG-only)
drive the suites without real HTTP, `state.vscdb`, or Keychain access. The
`CursorLocalTokenSource` suite builds a throwaway SQLite file to exercise the
real reader.
