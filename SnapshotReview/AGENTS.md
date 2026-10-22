# Snapshot Review — Module Group

Read the [repository contract](../AGENTS.md). See [README.md](README.md) for the group overview.

- Core owns review records, manifest types, discovery, and coordinated writes. It must not import SwiftUI, UIKit, or a snapshot engine.
- UI owns observable workspace state and rendering. The app creates one model and store and injects them.
- SnapshotKitTesting can depend on Core for metadata export. The app must never depend on SnapshotKitTesting.
- Keep image review status independent from todo status. A review applies to exactly one content fingerprint.
- File writes preserve external changes and missing-image annotations. Never overwrite malformed or unsupported files.
