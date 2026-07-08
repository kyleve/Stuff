# PeriscopeTools – Module Shape

PeriscopeTools is the on-device log exploration tooling for
[`PeriscopeCore`](../PeriscopeCore): the latest-logs viewer, the tracer, the
debug toast, and the log view mode modifier. See [`README.md`](README.md) for
the narrative and API.

This file complements the root [`AGENTS.md`](../../../AGENTS.md), which owns
the build system, formatting, and global conventions. Read that first.

## Scope & dependencies

- **SwiftUI + PeriscopeCore + PeriscopeUI.** No app code — app-specific
  wiring (which store, which alert handler) comes in via configuration.
- **Intended for DEBUG / developer surfaces**; consumers gate entry points
  behind `#if DEBUG`. Developer-facing strings are plain literals here.

## Invariants

- **Read-only over the store.** Tooling queries `PeriscopeCore`'s store and
  live buffer; it never records events of its own (except through the normal
  logging API).
- **The toast is hookable** — apps override the default handler rather than
  this module special-casing any app.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeToolsTests`). Seed an in-memory store, drive the view models
directly, and host views with `WhereTesting`'s `show()` helpers.
