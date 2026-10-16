# SnapshotKit todos

The item format and placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md).

# Open issues

## P1s (Should do)
- fix [needs-design]: Isolate models captured outside snapshot builders — the runner now invokes `SnapshotCase.content` per configuration (`../SnapshotKitTesting/Sources/AssertSnapshots.swift`), so models constructed inside the builder are fresh. Models captured outside the builder and mutations in case-level readiness hooks can still carry into later variants (`Sources/SnapshotCase.swift`). Migrate those cases to independent fixtures and hooks per configuration. The current mutable-hook regression covers models built inside the content factory. Add coverage for case-captured models and hooks before declaring complete isolation. (pr review, July 2026; narrowed during Duo foundation, 2026-10-14)

# Completed issues
