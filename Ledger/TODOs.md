# Ledger todos

The backlog for the Ledger menu bar app and `LedgerCore`. Ledger is native
macOS and sits outside the Where module graph, so the Bumper Bowling
architecture lint does not cover it (`BumperBowling.swift` includes only Where
paths) — the conventions below are enforced by review rather than by lint.

The item format and the placement rule live in the root
[`TODOs.md`](../TODOs.md); raw notes go in [`INBOX.md`](../INBOX.md), not here.

# Open issues

## P2s (Nice to have)
- fix(LedgerCore) [quick-win]: `LedgerServices` resolves its calendar from the device (`LedgerServices.swift:157`, `calendar: Calendar = .current` on the `@_spi(Testing)` init) and uses it for the today/this-week spend deltas (`:303-307`), so on a non-Gregorian system calendar the window boundaries `SpendHistory` differences against move — the same defect class Where forbids outright, and the parameter default also violates the repo's "avoid parameter defaults on Core APIs" rule, since the composition root already knows the value. Inject an explicit Gregorian calendar with the current time zone from the app, and pass it in tests rather than relying on the default. Lower severity than Where's equivalent: this shifts a spend window rather than corrupting stored day identity, and no value is persisted against it. (audit 2026-08-09)
- test(LedgerCore) [quick-win]: Three implementation files have no namesake test — `LedgerLog.swift`, `LedgerSettings.swift`, and `SpendSnapshot.swift`. Each is exercised indirectly through `LedgerServicesTests`, so this is 1:1-convention debt rather than untested behavior; close it as those files change rather than in one pass. The rest of the module is genuinely well covered (13 test files over 16 sources, including the API, Keychain, token-source, and history seams). Ledger shipped nothing at all this window, so all three counts are unchanged. (audit 2026-08-09; re-verified 2026-08-16)
- test(Ledger) [needs-design]: The `Ledger` app target ships no test bundle, so the eight sources in the SwiftUI/AppKit shell — `MenuBarLabel`, `SpendView`, `SettingsView`, `LedgerSession`, `CurrencyFormat`, `WindowVisibilityReader` — are compile-only in CI (`Ledger-macOS-Tests` builds the app but runs only `LedgerCoreTests`, `Project.swift:718-722`). This matches how the Where extension targets are treated and is documented in [`Ledger/AGENTS.md`](Ledger/AGENTS.md), so it is a deliberate gap rather than an oversight; the decision worth making is whether `CurrencyFormat` and the menu-bar label's formatting deserve a hostless bundle of their own, since they are pure value transforms that a test could pin cheaply. (audit 2026-08-09)

# Completed issues
