# SnapshotKit todos

The item format and placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md).

# Open issues

## P1s (Should do)
- fix [needs-design]: Isolate captured models between snapshot configurations — `SnapshotCase.content` invokes its factory (`Sources/SnapshotCase.swift:68-73`), but the runner evaluates it once per case (`../SnapshotKitTesting/Sources/AssertSnapshots.swift:49-51`) and re-hosts the same value for each configuration (`:121-122`). SwiftUI state reinitializes per host, while reference models captured by the builder and mutations from `onReadyToSnapshot` carry into later variants. Rebuild content inside the configuration loop and cover a mutating hook so one variant cannot affect another. The README, AGENTS.md, and accessor comment now describe the actual sharing; correcting the docs does not close the isolation work. (pr review, July 2026; re-verified 2026-09-07)

# Completed issues
