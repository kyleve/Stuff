# Patchlight — Know Where to Look

Patchlight is the second full Stuff product beside Where: an iPad and Mac
Catalyst code-review client that keeps GitHub review useful without AI, then
adds optional local BYOK analysis to direct human attention.

## Product contract

- One GitHub.com account and one app window in v1.
- Native cached repository/PR reading, deterministic triage, review drafts and
  writes, and a first-class PNG snapshot workspace.
- Optional OpenAI or Anthropic analysis using keys the user supplies. Requests
  go directly from the app to the selected provider; Patchlight has no backend,
  telemetry, automatic provider fallback, or automatic publication.
- iPad and Mac Catalyst only. Catalyst stays in the App Sandbox with outgoing
  network access and no shell or arbitrary filesystem design.

## Repository shape

```text
Patchlight/
├── PatchlightCore/   GitHub, diffs, policy, persistence, encryption, AI
├── PatchlightUI/     Broadway SwiftUI, UIKit diff rendering, developer tools
└── Patchlight/       thin @main host and process-runtime selection
```

`PatchlightCore` currently establishes the typed IDs/diff/review boundaries,
the stable `SnapshotAnnotationV1` marker, explicit local-only SwiftData v1
schema, encrypted draft persistence, account vault, and encrypted
content-addressed LRU. `PatchlightUI` establishes the lifecycle/Broadway root,
iPad split-view dashboard shell, localized onboarding surface, SnapshotKit
matrix, Flyover catalog, and DEBUG Inspector runtime. GitHub transport and the
full review workspace build on those seams in the following delivery stages.

## Security and persistence

Every signed-in GitHub account gets one `PatchlightScope`. Its 256-bit CryptoKit
key lives in Keychain; cached blobs, images, draft bodies, conversation payloads,
and AI payloads are encrypted before disk. SwiftData records never leave their
`@ModelActor`; views receive immutable Sendable values.

The cache defaults to 5 GB and offers 1/5/10/20 GB capacities. It is
content-addressed and LRU-evicted, but objects used by the open workspace are
protected. The account vault is excluded from backup and files are written
atomically.

Explicit GitHub sign-out cancels account work, deletes the account vault key
first, then removes account files and GitHub credentials. OpenAI and Anthropic
keys use independent app-global Keychain items and survive GitHub sign-out.

## Build and tests

Generate with `./ide --no-open`. Narrow checks are `./test PatchlightCoreTests`
and `./test PatchlightUITests`; image coverage is in the shared
`StuffSnapshotTests` scheme. The `Patchlight-Catalyst` shared scheme is built in
CI with `platform=macOS,variant=Mac Catalyst` because an iOS simulator build
does not prove Catalyst compilation.
