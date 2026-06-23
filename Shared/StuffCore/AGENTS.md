# StuffCore – Module Shape

StuffCore is a **scaffold** library: the repo slot for code shared across Stuff
apps. It currently exposes only a placeholder `version` constant so the module,
test bundle, and docs exist before the first real API lands. See
[`README.md`](README.md) for install and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **Foundation only** today. Keep it app-agnostic — no SwiftUI, UIKit, WhereCore,
  or feature-specific imports.
- Library target in [`Package.swift`](../../Package.swift),
  `Shared/StuffCore/Sources`; hosted tests in `StuffCoreTests` via the
  `unitTests` helper in [`Project.swift`](../../Project.swift) (host:
  `StuffTestHost`).

## Key types

- [`StuffCore`](Sources/StuffCore.swift) – namespace enum with `version`. Replace
  or extend this when the first shared type ships; bump `version` or remove it
  once real API makes the placeholder test unnecessary.

## Conventions

- Follow the root rules: exhaustive `switch` over enums, typed identifiers over
  raw strings, small named structs over tuples.
- When adding shared code, prefer minimal surface area and no feature imports —
  pull feature-specific wiring into the consumer module.

## Testing

Swift Testing in [`Tests/`](Tests) (never XCTest), hosted in `StuffTestHost`.
The placeholder `versionIsDefined` test should be replaced once real behavior
exists.
