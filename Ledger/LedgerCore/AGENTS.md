# LedgerCore – Module Shape

LedgerCore is the model layer for the Ledger menu bar app: a tree of
`@MainActor @Observable` objects rooted in `LedgerServices` that fetches the
current-cycle Cursor spend (and a year-to-date total) from Cursor's
undocumented dashboard API and reduces it to one observable `LoadState`. The
SwiftUI/AppKit layer lives in the app target ([`Ledger/Ledger`](../Ledger)) and
binds the tree directly; see [`README.md`](README.md) for the narrative and
per-type detail.

```
LedgerServices ── LedgerSettings (refresh interval)
       ├────────── SessionTokenSource ── CursorLocalTokenSource (state.vscdb, read-only)
       ├────────── KeychainStore (a pasted token override)
       ├────────── DashboardProvider ── CursorDashboardAPI (/api/usage-summary, get-monthly-invoice)
       └────────── LoginItemController (SMAppService)
```

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + Observation + Security + ServiceManagement + SQLite3 + LogKit
  only.** No SwiftUI, no AppKit UI — views and the thin session facade belong to
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
- **`onDemand.used` is "this cycle"; year-to-date = prior-month invoices + the
  live cycle figure.** The current month's invoice lags until charges post, so
  the live usage-summary number stands in for it — don't double-count by also
  summing the current month's (sparse) invoice.
- **Failures are observable, never swallowed.** Transport/HTTP/decode failures
  become a typed `DashboardError`, mapped into `LoadState.failed(LoadError)` and
  logged; 401 maps to `.notAuthenticated` (expired session). A stale response
  (an earlier fetch finishing after a newer one) is dropped via the request
  generation counter.
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
