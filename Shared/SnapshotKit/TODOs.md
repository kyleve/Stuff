# SnapshotKit todos

The item format and placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md).

# Open issues

## P1s (Should do)
- fix [needs-design]: Isolate captured models between ordinary snapshot configurations — `SnapshotCase.capture` stores a lazy single-view builder (`Sources/SnapshotCase.swift:69-74`), but the provider runner invokes it once before forwarding the complete configuration array (`../SnapshotKitTesting/Sources/AssertSnapshots.swift:62-66`); the inline runner reuses that view in its configuration loop (`:145-153`). SwiftUI state reinitializes per host, while captured reference models and readiness-hook mutations carry into later variants and settling retries. Rebuild ordinary content inside the configuration loop and cover a mutating hook. PR #436 adds a distinct cutsheet path whose panel builder is evaluated for each configuration (`../SnapshotKitTesting/Sources/AssertComparisonSnapshots.swift:19-26`, `:60-63`); that does not close ordinary-case isolation. Keep hook repeatability and retry semantics explicit. (pr review, July 2026; re-verified 2026-10-26)

# Completed issues
