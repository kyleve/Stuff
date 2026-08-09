# PatchlightCore

PatchlightCore is Patchlight's UI-free domain and infrastructure layer. It owns
typed GitHub/review models and boundaries, local patch/diff policy, account
persistence, encryption/cache security, and provider adapters.

The initial foundation includes:

- `RepositoryID`, `PullRequestID`, `GitObjectID`, and typed diff/hunk/line/anchor
  values;
- `GitHubReading`, `GitHubReviewWriting`, and `ReviewAnalysisProvider` seams;
- five monotonic `ReviewDepth` values and `ReviewAssessment`;
- `SnapshotAnnotationV1`'s interoperable base64url JSON comment marker;
- `PatchlightSchemaV1` plus a migration plan behind `PatchlightStore`, an
  `@ModelActor` that returns Sendable values only;
- CryptoKit-backed draft storage, an account Keychain vault key, and an
  encrypted content-addressed LRU cache using `ImageDiffKit` for future image
  comparison.

No SwiftUI or UIKit belongs here. Run `./test PatchlightCoreTests`.
