# PeriscopeUI – Module Shape

PeriscopeUI is the SwiftUI integration for [`PeriscopeCore`](../PeriscopeCore). It provides the `logContext` modifier and environment accessors that flow log scopes through a view hierarchy. See [`README.md`](README.md) for the narrative and API.

Read the root [`AGENTS.md`](../../../AGENTS.md) first. That file owns the build system, formatting, and global conventions.

## Scope & dependencies

- **Use SwiftUI and PeriscopeCore only.** Do not import app code. Developer tooling views live in [`PeriscopeTools`](../PeriscopeTools), not here.
- **Keep logging behavior, persistence, and policy in Core.** This module adapts Core to SwiftUI only.

## Invariants

- **Stacked `logContext` modifiers link, not replace.** A child's context is the union of every ancestor's scopes plus merged tags. The nearest modifier is primary (`Log.linked(with:)` semantics). Do not reimplement the merge here.
- **Keep the accumulated environment value optional.** A direct fallback would join a freeform scope into every explicit context.
- **`\.logContext` always yields a usable context.** Outside any modifier, it falls back to `LogContext()` on `Periscope.shared`.

## Testing

Swift Testing lives in [`Tests/`](Tests), hosted in `StuffTestHost` (`PeriscopeUITests`). Host views with `TestHostSupport`'s `show()` helpers. Assert against a fresh `Periscope` system per test.
