# StuffCore – Module Shape

Shared library — **Foundation only**, no app/SwiftUI imports, so every module
(incl. `WhereCore`, which must not import SwiftUI directly) can depend on it.

Complements root [`AGENTS.md`](../../AGENTS.md). Tests: `StuffCoreTests` in
`StuffTestHost` (`tuist test StuffCoreTests`).

## Key types

- [`StuffCore`](Sources/StuffCore.swift) — version placeholder until shared
  non-localization code lands here. Localization tooling lives in
  [`LocalizationKit`](../LocalizationKit/).

## Testing

Tests live in [`Tests/`](Tests) (Swift Testing only). See
[`StuffCoreTests`](Tests/StuffCoreTests.swift).
