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
  reauthorization fallback states.

No SwiftUI or UIKit belongs here. Run `./test PatchlightCoreTests`.
