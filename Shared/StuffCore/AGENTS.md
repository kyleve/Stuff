# StuffCore – Module Shape

Shared library — **Foundation only**, no app/SwiftUI imports, so every module
(incl. `WhereCore`, which must not import SwiftUI) can depend on it.

Complements root [`AGENTS.md`](../../AGENTS.md). Tests: `StuffCoreTests` in
`StuffTestHost` (`tuist test StuffCoreTests`).

## Key types

- [`LocalizedString`](Sources/LocalizedString.swift) — a **deferred** localized
  string. Wraps a `(LocalizationConfig?) -> String` builder; `.localized(_:)`
  runs it. Producers return this instead of `String` so the catalog lookup (and
  locale choice) happens at display time. Non-`Sendable` for now (the UI pilot
  doesn't cross actor boundaries); mark the builder `@Sendable` and conform when
  a `Sendable` consumer like `WhereCore` adopts it.
- [`LocalizationConfig`](Sources/LocalizedString.swift) — `Sendable, Hashable`
  value type carrying the `locale` to resolve against. `nil` means "process
  default" (`.current`).

## Invariants / conventions

- The builder closure should perform a `String(localized:bundle:locale:)` lookup
  against the **owning module's** catalog — `StuffCore` itself ships no catalog,
  so each module defines a thin `.module(_:_:)` factory that captures its own
  `Bundle.module` (see WhereUI's `LocalizedString+Module.swift`).
- Per-module `LocalizedStrings.swift` enums are the canonical producers; the
  root `localize` script parses those literal `.module("<key>", "<value>")`
  factory calls (and the raw `String(localized:defaultValue:…)` form used by
  composed members) — see root
  [`AGENTS.md`](../../AGENTS.md#keeping-localization-in-sync). Keep the key and
  default value as **string literals** (the key is a `StaticString`) — anything
  dynamic makes the script fail loudly rather than drift silently.
- Resolution is lazy: referencing a `LocalizedString` does no work; only
  `.localized` reads the catalog. Don't cache resolved `String`s where a
  locale override might later apply.
