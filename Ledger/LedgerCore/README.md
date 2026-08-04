# LedgerCore

The model layer for the **Ledger** menu bar app: it fetches your current
Cursor billing-cycle spend from the same
undocumented dashboard endpoints the `cursor.com/dashboard/usage` page uses,
authenticated with your Cursor **session token**. The SwiftUI/AppKit shell
lives in the [`Ledger`](../Ledger) app target and binds this tree directly.

## What it does

- Resolves a session token — **auto-detected** from your local Cursor app
  (`state.vscdb` → `cursorAuth/accessToken`), or a value you **paste** into
  Settings (stored in the Keychain, which overrides auto-detect).
- Calls `GET /api/usage-summary` for the current cycle's dates, plan type, and
  live usage-based spend, and `POST /api/dashboard/get-filtered-usage-events`
  (paginated over the cycle) for the per-model breakdown (best-effort).
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
- `ModelName` — parses a raw model id (`claude-opus-4-8-thinking-xhigh`,
  `github_bugbot`, …) into a friendly `displayName` + `badges` (effort/speed/mode).
- `UsageSummary`, `UsageEvent`/`UsageEventsPage`, `SpendSnapshot` — the wire + view models
  (cents are integers).
- `KeychainStore` / `SystemKeychainStore` — a pasted token's storage.
- `LedgerSettings` / `LedgerConfiguration` / `LedgerConfigStore` — the persisted
  refresh interval (no secrets).
- `LoginItemController` — launch-at-login via `SMAppService`.
- `LedgerLog` — the LogKit logging facade (subsystem `com.stuff.ledger`).

## How the figures are computed

- **This cycle** = `usage-summary` → `individualUsage.onDemand.used` (cents),
  the live usage-based spend.
- **Today / this week** = differences of the cumulative `onDemand.used` across
  locally recorded samples (`SpendSample` / `SpendHistoryStore` / `SpendHistory`).
  Because that value is a server-side running total, the difference between two
  samples is real billed spend for the interval — even across times the app
  wasn't running — as long as a sample exists near the window's start. Baselines
  are scoped to the current cycle; each figure is `nil` (hidden) until there's
  enough history. The API itself exposes no per-range billed figure, so this
  local differencing is the only reliable way to get it.
- There is deliberately **no year-to-date total**: the `get-monthly-invoice`
  endpoint is a billing ledger with cross-month adjustments (negative
  "mid-month usage paid for <month>" credit lines) whose contents shift as
  billing settles, so summing months doesn't yield a meaningful "spend this
  year" (it can even go negative). Rather than show a wrong number, Ledger omits
  it.

- **Model shares** = per-event `chargedCents` from `get-filtered-usage-events`
  (paginated over the cycle), summed per model, each shown as a **share** of the
  total (all models, highest first; the UI rolls sub-5% shares into one bar).
  Deliberately dollar-free: that summed cost is *total usage value* (included
  allowance + on-demand), so it exceeds the billed on-demand headline and must
  not be presented as spend. (The older `get-aggregated-usage-events` was
  dropped — it goes stale and omits recently released models.) Best-effort — a
  failure logs and keeps the last good breakdown rather than failing the load.

  Walking every event costs several paginated requests, so this fetch is
  **throttled to at most every 15 minutes** instead of running at the headline
  refresh cadence (which can be as fast as once a minute). The cached breakdown
  is reused in between; the popover's **Refresh** button forces a fresh fetch,
  as does a new billing cycle.

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
