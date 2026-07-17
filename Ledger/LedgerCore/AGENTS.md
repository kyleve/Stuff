# LedgerCore – Module Shape

LedgerCore is the model layer for the Ledger menu bar app: a tree of
`@MainActor @Observable` objects rooted in `LedgerServices` that fetches the
current-cycle Cursor spend from the Admin API and reduces it to the signed-in
member. The SwiftUI/AppKit layer lives in the app target
([`Ledger/Ledger`](../Ledger)) and binds the tree directly; see
[`README.md`](README.md) for the narrative and per-type detail.

```
LedgerServices ── LedgerSettings (email, interval)
       ├────────── KeychainStore (Admin API key)
       ├────────── SpendProvider ── CursorSpendAPI (POST /teams/spend)
       ├────────── LedgerConfigStore (LedgerConfiguration JSON)
       └────────── LoginItemController (SMAppService)
```

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns the
build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation + Observation + Security + ServiceManagement + LogKit only.** No
  SwiftUI, no AppKit UI — views and the thin session facade belong to the app
  target. LedgerCore is the repo's only macOS-only package library
  (`.macOS(.v26)` in [`Package.swift`](../../Package.swift)).
- The hostless macOS test bundle `LedgerCoreTests` is declared directly in
  [`Project.swift`](../../Project.swift) and runs via the `Ledger-macOS-Tests`
  scheme.

## Invariants

- **One `LoadState`, never a mix.** Success, failure, loading, and "not loaded
  yet" are the four cases of `LedgerServices.LoadState` — the UI reads exactly
  one. Don't reintroduce parallel `isLoading` / `error` / `value` fields.
- **The API key never touches disk-in-plaintext.** It lives only in the
  Keychain (`KeychainStore`); `LedgerConfiguration` persists the email and
  refresh interval and nothing else. Never add the key to the JSON.
- **Filter to the member client-side, by email, case-insensitively.** The
  request sends `{}` (the whole team) and `SpendResponse.member(matching:)`
  selects the row — a `searchTerm` on the wire could hide a renamed account.
  No match is `LoadError.memberNotFound`, not an empty success.
- **`totalCents` prefers `overallSpendCents`,** falling back to `spendCents +
  includedSpendCents` only when the API omits it — so the headline figure is
  never silently short. Cent fields are `Double` (sub-cent precision), not Int.
- **Failures are observable, never swallowed.** Transport/HTTP/decode failures
  become a typed `SpendProviderError`, mapped into `LoadState.failed(LoadError)`
  and logged; a stale response (an earlier fetch finishing after a newer one)
  is dropped via the request generation counter, not applied.
- **The login item is OS-owned, not persisted config.** `LoginItemController`
  reads/writes `SMAppService.mainApp` (behind an `@_spi(Testing)` backend) as a
  typed `LoginItemStatus`; `requiresApproval` counts as *on*. `startsAtLogin`
  is a live read, and its setter surfaces failures on `loginItemError` while
  keeping the observed value honest.
- **Absence vs failure.** A missing config file is `.initial`; a file that
  exists but can't be decoded throws rather than silently resetting.

## Testing

Swift Testing in [`Tests/`](Tests), hostless on macOS (`tuist test
LedgerCoreTests -- -destination 'platform=macOS'`). Shared fixtures live in
[`LedgerCoreTestSupport.swift`](Tests/LedgerCoreTestSupport.swift). The network
and Keychain seams use the module's `@_spi(Testing)` DEBUG doubles
(`ScriptedSpendProvider`, `InMemoryKeychainStore`); filesystem tests use unique
temp directories and never touch the user's real Application Support or
Keychain.
