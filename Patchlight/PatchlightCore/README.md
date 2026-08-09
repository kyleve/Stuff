# PatchlightCore

PatchlightCore is Patchlight's UI-free domain and infrastructure layer. It owns
typed GitHub/review models and boundaries, local patch/diff policy, account
persistence, encryption/cache security, and provider adapters.

The shipping foundation includes:

- `RepositoryID`, `PullRequestID`, `GitObjectID`, and typed diff/hunk/line/anchor
  values;
- `GitHubReading`, `GitHubReviewWriting`, and `ReviewAnalysisProvider` seams;
- five monotonic `ReviewDepth` values and `ReviewAssessment`;
- `SnapshotAnnotationV1`'s interoperable base64url JSON comment marker;
- `PatchlightSchemaV1` plus a migration plan behind `PatchlightStore`, an
  `@ModelActor` that returns Sendable values only;
- CryptoKit-backed draft storage, an account Keychain vault key, and an
  encrypted content-addressed LRU cache using `ImageDiffKit` for image
  comparison;
- secretless GitHub App device flow with expiring-token refresh rotation and a
  DEBUG-only fine-grained PAT seam;
- fixed-host GitHub transport, installation/repository/direct/team/self-PR
  discovery, pagination, ETags, rate-limit and partial-response handling;
- local unified-patch parsing and a cancellable, bounded Myers fallback for
  omitted text patches; and
- encrypted dashboard/repository/workspace snapshots with honest offline and
  reauthorization fallback states;
- review conversations, checks, inline threads, and encrypted offline copies;
- one-shot GitHub review/comment/thread/viewed mutations with ambiguous-write
  reconciliation and no automatic retry; and
- stale-head draft remapping that accepts only a unique path/rename plus
  context fingerprint and otherwise requires an explicit user decision;
- `DeterministicReviewAnalyzer`, versioned `.patchlight.json` decoding, and
  case-sensitive slash-normalized glob matching for the five-depth safety
  policy, per-head corrections, and snapshot routing; and
- `SnapshotWorkspaceCoordinator`, which loads exact base/head blob identities
  through the protected encrypted cache and delegates authoritative local pixel
  comparison and heatmap generation to shipping `ImageDiffKit`.

No SwiftUI or UIKit belongs here. Run `./test PatchlightCoreTests`.
