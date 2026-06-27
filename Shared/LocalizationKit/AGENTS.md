# LocalizationKit – Module Shape

Framework-level localization tooling — **Foundation + SwiftUI**. Each app module
(WhereUI, WhereCore, …) depends on this for `LocalizedString` and the SwiftUI
helpers, then keeps its own `LocalizedStrings.swift` catalog and a thin
`.module(_:_:)` wrapper binding `Bundle.module`.

Complements root [`AGENTS.md`](../../AGENTS.md). Tests: `LocalizationKitTests`
in `StuffTestHost` (`tuist test LocalizationKitTests`).

## Key types

- [`LocalizedString`](Sources/LocalizedString.swift) — a **deferred** localized
  string. Wraps a `@Sendable (LocalizationConfig?) -> String` builder;
  `.localized(_:)` runs it. `Sendable`, so a `LocalizedString` can be cached in a
  `static let` and cross isolation boundaries.
- [`LocalizationConfig`](Sources/LocalizedString.swift) — `Sendable, Hashable`
  value type carrying the `locale` to resolve against. `nil` means "process
  default" (`.current`).
- [`LocalizedString.catalog(_:_:bundle:)`](Sources/LocalizedString+Catalog.swift)
  — the generic factory. Each consumer module defines a thin `.module(_:_:)`
  that passes `bundle: .module` (see WhereUI's `LocalizedString+Module.swift`).
- [`Text(localized:)`](Sources/Text+Localized.swift) and
  [`View` overloads](Sources/View+Localized.swift) — resolve at display time.

## Invariants / conventions

- LocalizationKit ships **no catalog** — only the types and helpers. Keys and
  English defaults live in each module's `LocalizedStrings.swift`; the root
  `./localize` script parses literal `.module("<key>", "<value>")` factory calls
  (and the closure overload) — see root
  [`AGENTS.md`](../../AGENTS.md#keeping-localization-in-sync).
- Keep the key and default value as **string literals** (the key is a
  `StaticString`) — anything dynamic makes the script fail loudly rather than
  drift silently.
- Resolution is lazy: referencing a `LocalizedString` does no work; only
  `.localized` reads the catalog. Don't cache resolved `String`s where a
  locale override might later apply.

## Testing

Tests live in [`Tests/`](Tests) (Swift Testing only). The bundle runs in
`StuffTestHost`. See [`LocalizedStringTests`](Tests/LocalizedStringTests.swift).
