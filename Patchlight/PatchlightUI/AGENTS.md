# PatchlightUI – Module Shape

Patchlight's lifecycle/presentation layer; see [`README.md`](README.md), the
product [`AGENTS.md`](../AGENTS.md), and root [`AGENTS.md`](../../AGENTS.md).

May depend on `PatchlightCore` and shared UI/tooling modules. Keep persistence,
HTTP, cryptography, and policy in Core. Build every surface through the
Patchlight Broadway root, use native adaptive iPad/Catalyst layout, provide
localized accessibility labels, a `#Preview`, and a SnapshotKit matrix for
meaningful states. The UIKit diff bridge belongs here and receives typed rows.

Lifecycle composition creates or receives one account scope and injects it
down; views never re-resolve it. DEBUG Inspector/Flyover/Periscope worlds stay
isolated from production persistence.

Tests: `PatchlightUITests`; images: `PatchlightUISnapshotTests` in
`StuffSnapshotTests`.
