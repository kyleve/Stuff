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

`PatchlightCore` owns the typed IDs/diff/review boundaries, stable
`SnapshotAnnotationV1` marker, explicit local-only SwiftData v1 schema,
encrypted persistence/cache, GitHub device authentication, API pagination,
patch parsing, and bounded local Myers fallback. `PatchlightUI` owns the
lifecycle/Broadway root, onboarding, cached dashboard, repository browser,
dedicated PR workspace, and the native virtualized diff renderer, plus Flyover,
snapshot, Inspector, and Periscope developer surfaces.

The workspace supports encrypted line/file drafts, issue and review discussion,
inline thread replies and resolution, checks, batched review submission, and
GitHub viewed state. Writes are always user initiated. Patchlight never retries
an ambiguous write; it refreshes and proves the result when possible, otherwise
retains the draft and labels the status uncertain. A changed head freezes drafts
until their anchors are uniquely remapped or explicitly resolved.

Every retrieved hunk first passes through a deterministic attention policy. The
five snapped depths run from Critical through Everything, preserve hard safety
signals, and keep incomplete content visible. Optional base-revision
`.patchlight.json` rules and encrypted local overrides can identify review,
generated, mechanical, test, and snapshot paths; a configuration changed by the
PR never governs its own review. Corrections are local to one head SHA.

PNG snapshots route into a dedicated virtualized workspace with grouped
browsing, synchronized zoom, side-by-side, wipe, opacity overlay, and a locally
generated pixel heatmap. Region annotations post as ordinary visible GitHub
file comments with the versioned `SnapshotAnnotationV1` marker, so matching
blobs can render the region and older blobs remain visibly outdated.

The GitHub-only build remains useful offline: successful dashboard, repository,
and workspace reads are encrypted locally, stale data is visibly labeled, and
authentication expiry preserves that data for reauthorization. The GitHub App
client ID and slug are non-secret build settings (`PATCHLIGHT_GITHUB_CLIENT_ID`
and `PATCHLIGHT_GITHUB_APP_SLUG`); the owner supplies them for a distributable
build.

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
