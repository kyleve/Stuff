# LedgerCore – Module Shape

LedgerCore is the model layer for the Ledger menu bar app: a tree of
`@MainActor @Observable` objects rooted in `LedgerServices` that fetches the
current-cycle Cursor spend from Cursor's
undocumented dashboard API and reduces it to one observable `LoadState`. The
SwiftUI/AppKit layer lives in the app target ([`Ledger/Ledger`](../Ledger)) and
binds the tree directly; see [`README.md`](README.md) for the narrative and
per-type detail.

```
LedgerServices ── LedgerSettings (refresh interval)
       ├────────── SessionTokenSource ── CursorLocalTokenSource (state.vscdb, read-only)
       ├────────── KeychainStore (a pasted token override)
       ├────────── DashboardProvider ── CursorDashboardAPI (usage-summary, get-filtered-usage-events)
       └────────── LoginItemController (SMAppService)
```

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + Observation + Security + ServiceManagement + SQLite3 +
  PeriscopeCore only.** No SwiftUI, no AppKit UI — views and the thin session
  facade belong to
  the app target. LedgerCore is the repo's only macOS-only package library
  (`.macOS(.v26)` in [`Package.swift`](../../Package.swift)).
- The hostless macOS test bundle `LedgerCoreTests` is declared directly in
  [`Project.swift`](../../Project.swift) and runs via the `Ledger-macOS-Tests`
  scheme.

## Invariants

- **One `LoadState`, never a mix.** Success, failure, loading, and "not loaded
  yet" are the four cases of `LedgerServices.LoadState` — the UI reads exactly
  one.
- **Auth is a session cookie, not an API key.** The cookie value must be
  `"<userId>::<jwt>"`; `SessionToken` derives the `userId` from the JWT `sub`
  when given a bare JWT (as the local Cursor app stores it). A raw JWT alone is
  a guaranteed 401 — never send it un-prefixed.
- **Token precedence: pasted overrides auto.** A Keychain token wins; otherwise
  the local Cursor session (`CursorLocalTokenSource`) is used. No token at all
  is `LoadError.missingCredentials`.
- **Read Cursor's `state.vscdb` read-only.** Open with `SQLITE_OPEN_READONLY`
  and never write/lock it — Cursor may hold it open. Any failure (missing file,
  missing key, locked) degrades to "no auto-token" (`nil`), not a throw.
- **`onDemand.used` is "this cycle"; there is no year-to-date total.** The
  `get-monthly-invoice` endpoint is a billing ledger with cross-month
  adjustments (negative "mid-month usage paid for <month>" credits) whose
  contents shift as billing settles, so summing months is not a meaningful
  yearly spend (it can go negative). Don't reintroduce a summed YTD.
- **Today/this-week spend is differenced from local history, not the API.**
  `onDemand.used` is a cycle-cumulative running total, so `SpendHistory` diffs
  recorded `SpendSample`s (baseline scoped to the current cycle) to get
  per-window spend — real billed dollars, unlike the per-model usage figures.
  A window with no baseline returns `nil` (hidden), never a guessed number;
  deltas clamp at 0. History persistence (`SpendHistoryStore`) is best-effort.
- **Per-model usage is a dollar-free share, from the fresh per-event endpoint.**
  `ModelShare.shares(from:)` sums `get-filtered-usage-events`' per-event
  `chargedCents` per model (the aggregated endpoint is stale for some accounts
  and omits recent models). That summed cost is *total usage value* (included
  allowance + on-demand), which exceeds the billed on-demand headline, so
  `ModelShare` carries only a fraction — never present it as spend next to the
  headline. `LedgerServices.cycleEvents` paginates the cycle (capped,
  newest-first, no `teamId`), which costs several requests, so it is
  **throttled** (`modelRefreshInterval`) rather than refetched at the headline
  cadence — the cache is reused in between, and bypassed only by an explicit
  `refresh(force: true)` or a cycle rollover. Best-effort — a failure logs and
  keeps the last good breakdown.
- **Only the newest refresh may mutate state.** `refresh` stamps a generation
  and everything after the fetch — recording history included — runs behind the
  `generation == requestGeneration` guard. A superseded response recording
  history would append an older reading at a later timestamp and skew future
  day/week baselines.
- **Failures are observable, never swallowed.** Transport/HTTP/decode failures
  become a typed `DashboardError`, mapped into a `LoadError` and logged; 401
  maps to `.notAuthenticated` (expired session). A slow response superseded by a
  newer fetch is dropped via the request-generation counter.
- **A failed refresh keeps prior data (stale), not blanks it.** If spend is
  already `.loaded`, a failure keeps the last snapshot on screen and surfaces on
  `loadError` (the UI shows a stale "Updated…" warning); only a failure with
  nothing loaded yet becomes `LoadState.failed`. Success clears `loadError`.
- **The login item is OS-owned, not persisted config** (see
  `LoginItemController`); `startsAtLogin` is a live read whose setter keeps the
  observed value honest and surfaces failures on `loginItemError`.
- **No secrets in JSON.** `LedgerConfiguration` persists only the refresh
  interval; a pasted token lives in the Keychain, the auto-token in Cursor's own
  store.

## Testing

Swift Testing in [`Tests/`](Tests), hostless on macOS (`tuist test
LedgerCoreTests -- -destination 'platform=macOS'`). Shared fixtures live in
[`LedgerCoreTestSupport.swift`](Tests/LedgerCoreTestSupport.swift). The network,
token-source, and Keychain seams use the module's `@_spi(Testing)` DEBUG doubles
(`ScriptedDashboardProvider`, `StubTokenSource`, `InMemoryKeychainStore`); the
`CursorLocalTokenSource` suite builds a throwaway SQLite file, and other
filesystem tests use unique temp directories — never the user's real state,
Application Support, or Keychain.
