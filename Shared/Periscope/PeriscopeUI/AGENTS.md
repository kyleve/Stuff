# PeriscopeUI – Module Shape

PeriscopeUI is the SwiftUI integration for
[`PeriscopeCore`](../PeriscopeCore): the `logContext` modifier and
environment accessors that flow log scopes through a view hierarchy. See
[`README.md`](README.md) for the narrative and API.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **SwiftUI + PeriscopeCore.** No app code; the developer tooling views live
  in [`PeriscopeTools`](../PeriscopeTools), not here.
- This module adapts Core to SwiftUI — logging behavior, persistence, and
  policy all belong in Core.

## Invariants

- **Stacked `logContext` modifiers link, not replace** — a child's context is
  the union of every ancestor's scopes plus merged tags, nearest modifier
  primary (`Log.linked(with:)` semantics; don't reimplement the merge here).
- **`\.logContext` always yields a usable logger** — outside any modifier it
  falls back to a root `Log<Message>` on `Periscope.shared`, mirroring
  `Log.current`.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeUITests`). Host views with `TestHostSupport`'s `show()` helpers and
assert against a fresh `Periscope` system per test.
